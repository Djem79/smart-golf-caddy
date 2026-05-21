// Firestore security-rules test. Runs against the emulator:
//   npm run test:rules   (wraps `firebase emulators:exec --only firestore`)
//
// Standalone Node script (not vitest) so it doesn't collide with the jsdom
// unit suite that mocks firebase. Asserts the Sprint-7 + audit hardening:
// clients can never write `players` (join is callable-only), server-only
// fields are blocked, and leave/start/finish still work for the right actor.
import { readFileSync } from 'node:fs'
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing'
import { doc, setDoc, getDoc, updateDoc } from 'firebase/firestore'

const HOST = 'host-uid'
const ALICE = 'alice-uid' // participant
const MALLORY = 'mallory-uid' // participant attacker
const OUTSIDER = 'outsider-uid' // non-participant

function lobbyRound() {
  return {
    courseId: 'c1',
    courseName: 'Test Course',
    totalHoles: 9,
    lobbyCode: 'ABC123',
    status: 'lobby',
    hostId: HOST,
    players: {
      [HOST]: { name: 'Host', avatar: '', email: 'host@example.com' },
      [ALICE]: { name: 'Alice', avatar: '', email: 'alice@example.com' },
      [MALLORY]: { name: 'Mallory', avatar: '', email: 'mallory@example.com' },
    },
    playerIds: [HOST, ALICE, MALLORY],
    holes: [{ holeNumber: 1, par: 4, distanceMeters: 360, shots: {} }],
    startedAt: null,
    finishedAt: null,
    createdAt: new Date(),
  }
}

const testEnv = await initializeTestEnvironment({
  projectId: 'smart-golf-caddy-rules-test',
  firestore: { rules: readFileSync('firestore.rules', 'utf8') },
})

const host = testEnv.authenticatedContext(HOST).firestore()
const alice = testEnv.authenticatedContext(ALICE).firestore()
const mallory = testEnv.authenticatedContext(MALLORY).firestore()
const outsider = testEnv.authenticatedContext(OUTSIDER).firestore()

async function seed(id, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'rounds', id), data)
  })
}

let passed = 0
let failed = 0
async function test(name, fn) {
  try {
    await fn()
    passed++
    console.log('  ✓', name)
  } catch (e) {
    failed++
    console.error('  ✗', name, '\n      ', e.message)
  }
}

try {
  // --- The headline fix: PII forgery via the old JOIN rule is closed ---
  await seed('r1', lobbyRound())
  await test("participant CANNOT forge another player's email", async () => {
    const players = lobbyRound().players
    players[ALICE].email = 'attacker@evil.com'
    await assertFails(updateDoc(doc(mallory, 'rounds', 'r1'), { players }))
  })
  await test('client CANNOT write players at all (join is callable-only)', async () => {
    await assertFails(
      updateDoc(doc(mallory, 'rounds', 'r1'), {
        players: { ...lobbyRound().players, 'new-uid': { name: 'X', avatar: '', email: '' } },
        playerIds: [HOST, ALICE, MALLORY, 'new-uid'],
      }),
    )
  })

  // --- Legitimate per-action updates still work ---
  await seed('r2', lobbyRound())
  await test('participant CAN leave (remove only self from playerIds)', async () => {
    await assertSucceeds(updateDoc(doc(alice, 'rounds', 'r2'), { playerIds: [HOST, MALLORY] }))
  })
  await seed('r3', lobbyRound())
  await test('participant CANNOT remove a different player', async () => {
    await assertFails(updateDoc(doc(alice, 'rounds', 'r3'), { playerIds: [HOST, ALICE] }))
  })
  await seed('r4', lobbyRound())
  await test('host CAN start (lobby -> active)', async () => {
    await assertSucceeds(updateDoc(doc(host, 'rounds', 'r4'), { status: 'active', startedAt: new Date() }))
  })
  await seed('r5', lobbyRound())
  await test('non-host CANNOT start', async () => {
    await assertFails(updateDoc(doc(alice, 'rounds', 'r5'), { status: 'active', startedAt: new Date() }))
  })
  const active = lobbyRound()
  active.status = 'active'
  active.startedAt = new Date()
  await seed('r6', active)
  await test('host CAN finish (active -> finished)', async () => {
    await assertSucceeds(updateDoc(doc(host, 'rounds', 'r6'), { status: 'finished', finishedAt: new Date() }))
  })

  // --- Server-only fields blocked from any client ---
  await seed('r7', active)
  await test('client CANNOT write holes (server-only)', async () => {
    await assertFails(
      updateDoc(doc(host, 'rounds', 'r7'), {
        holes: [{ holeNumber: 1, par: 3, distanceMeters: 100, shots: {} }],
      }),
    )
  })
  await test('client CANNOT write emailedTo (server-only)', async () => {
    await assertFails(updateDoc(doc(host, 'rounds', 'r7'), { emailedTo: { [HOST]: true } }))
  })

  // --- Read guard: participant-only ---
  await seed('r8', lobbyRound())
  await test('participant CAN read the round', async () => {
    await assertSucceeds(getDoc(doc(alice, 'rounds', 'r8')))
  })
  await test('non-participant CANNOT read the round', async () => {
    await assertFails(getDoc(doc(outsider, 'rounds', 'r8')))
  })
} finally {
  await testEnv.cleanup()
}

console.log(`\n${passed} passed, ${failed} failed`)
process.exit(failed === 0 ? 0 : 1)
