// Offline-resilient shot recording.
//
// `recordShot` is a Cloud Function callable — it needs connectivity and has no
// offline support, which is a problem on a golf course with patchy signal.
// This module wraps it with a durable local queue: a shot is persisted to
// localStorage first, then sent; if the send fails because we're offline (or
// hits a transient server error) the entry stays queued and is flushed when
// connectivity returns (`online` event + app start).
//
// Safe because `recordShot` is idempotent: it writes the FULL clubs array for a
// hole's slot (not an increment). So the queue only needs the latest desired
// state per `round:hole:player` slot, and replaying is last-write-wins.
import { recordShot } from './rounds'

export interface PendingShot {
  roundId: string
  holeIndex: number
  targetUid: string
  clubs: string[]
  updatedAt: number
}

const KEY = 'sgc_pending_shots_v1'

// Server rejections that will NEVER succeed on retry — drop these from the
// queue and let the caller surface an error instead of looping forever.
const PERMANENT_CODES = new Set([
  'permission-denied',
  'unauthenticated',
  'failed-precondition',
  'invalid-argument',
  'not-found',
])

function slotKey(roundId: string, holeIndex: number, targetUid: string): string {
  return `${roundId}:${holeIndex}:${targetUid}`
}

function load(): Record<string, PendingShot> {
  try {
    const raw = localStorage.getItem(KEY)
    return raw ? (JSON.parse(raw) as Record<string, PendingShot>) : {}
  } catch {
    return {}
  }
}

function persist(map: Record<string, PendingShot>): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(map))
  } catch {
    /* quota / private mode — the in-flight send is still attempted */
  }
}

function sameClubs(a: string[], b: string[]): boolean {
  return a.length === b.length && a.every((c, i) => c === b[i])
}

export function enqueueShot(entry: Omit<PendingShot, 'updatedAt'>): void {
  const map = load()
  map[slotKey(entry.roundId, entry.holeIndex, entry.targetUid)] = {
    ...entry,
    updatedAt: Date.now(),
  }
  persist(map)
}

// Remove a slot only if its queued clubs still equal what we just sent — avoids
// clobbering a newer shot the user recorded on the same hole while the send was
// in flight.
function dequeueIfMatches(roundId: string, holeIndex: number, targetUid: string, clubs: string[]): void {
  const map = load()
  const k = slotKey(roundId, holeIndex, targetUid)
  if (map[k] && sameClubs(map[k].clubs, clubs)) {
    delete map[k]
    persist(map)
  }
}

export function getPendingShot(
  roundId: string,
  holeIndex: number,
  targetUid: string,
): PendingShot | undefined {
  return load()[slotKey(roundId, holeIndex, targetUid)]
}

export function pendingCountForRound(roundId: string): number {
  return Object.values(load()).filter(e => e.roundId === roundId).length
}

interface RecordResult {
  synced: boolean
}

// Record a shot durably: queue it, then try to sync. Returns `synced: false`
// when it stayed queued (offline / transient failure). Throws only on a
// permanent rejection (after dropping it from the queue) so the caller can
// roll back the optimistic UI.
export async function recordShotQueued(
  roundId: string,
  holeIndex: number,
  targetUid: string,
  clubs: string[],
): Promise<RecordResult> {
  enqueueShot({ roundId, holeIndex, targetUid, clubs })

  if (typeof navigator !== 'undefined' && navigator.onLine === false) {
    return { synced: false }
  }

  try {
    await recordShot(roundId, holeIndex, targetUid, clubs)
    dequeueIfMatches(roundId, holeIndex, targetUid, clubs)
    return { synced: true }
  } catch (err) {
    const raw = (err as { code?: string })?.code ?? ''
    const code = raw.replace(/^functions\//, '')
    if (PERMANENT_CODES.has(code)) {
      dequeueIfMatches(roundId, holeIndex, targetUid, clubs)
      throw err
    }
    // Transient (offline/unavailable/internal) — keep queued for later flush.
    return { synced: false }
  }
}

let flushing = false

// Flush every queued shot. Stops on the first transient failure (still offline)
// to avoid hammering. Permanent rejections are dropped so they don't wedge the
// queue. Returns the number of entries still pending afterwards.
export async function flushQueue(): Promise<{ remaining: number }> {
  if (flushing) return { remaining: Object.keys(load()).length }
  flushing = true
  try {
    for (const [k, entry] of Object.entries(load())) {
      try {
        await recordShot(entry.roundId, entry.holeIndex, entry.targetUid, entry.clubs)
        const cur = load()
        if (cur[k] && cur[k].updatedAt === entry.updatedAt) {
          delete cur[k]
          persist(cur)
        }
      } catch (err) {
        const code = ((err as { code?: string })?.code ?? '').replace(/^functions\//, '')
        if (PERMANENT_CODES.has(code)) {
          const cur = load()
          if (cur[k] && cur[k].updatedAt === entry.updatedAt) {
            delete cur[k]
            persist(cur)
          }
          continue // drop and keep going
        }
        break // transient — stop this pass, try again on next online event
      }
    }
    return { remaining: Object.keys(load()).length }
  } finally {
    flushing = false
  }
}

// Register background sync: flush on startup and whenever connectivity returns.
let initialised = false
export function initShotSync(): void {
  if (initialised || typeof window === 'undefined') return
  initialised = true
  window.addEventListener('online', () => {
    void flushQueue()
  })
  void flushQueue()
}
