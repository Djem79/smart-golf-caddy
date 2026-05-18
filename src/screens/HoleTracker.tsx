import { useState, useEffect, useCallback, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { useAppStore } from '../store/useAppStore'
import { subscribeToRound, recordShot, finishRound } from '../services/rounds'
import type { Round } from '../types'
import { DEFAULT_CLUBS, CLUB_ABBREV, getHoleClubs } from '../types'
import { ClubChip } from '../components/ui/ClubChip'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'

export function HoleTracker() {
  const { roundId, holeNumber } = useParams<{ roundId: string; holeNumber: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const { lastClubUsed, setLastClubUsed } = useAppStore()

  const holeIndex = parseInt(holeNumber ?? '1', 10) - 1
  const [round, setRound] = useState<Round | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [finishing, setFinishing] = useState(false)

  // Optimistic state — reconciled by snapshot updates
  const [localClubs, setLocalClubs] = useState<string[] | null>(null)
  const lastSyncedKeyRef = useRef<string | null>(null)

  // What club the user has currently highlighted in the chip row.
  // Independent from recording — only the +/− buttons write shots.
  const [selectedClub, setSelectedClub] = useState<string>(lastClubUsed)

  useEffect(() => {
    if (!roundId) return
    return subscribeToRound(roundId, setRound)
  }, [roundId])

  const hole = round?.holes[holeIndex]
  const serverClubs = (hole && user) ? getHoleClubs(hole.shots[user.uid]) : []
  const serverKey = serverClubs.join('|')

  // Reset optimistic state when navigating to a new hole
  useEffect(() => {
    setLocalClubs(null)
    lastSyncedKeyRef.current = null
    setSelectedClub(lastClubUsed)
  }, [holeIndex, lastClubUsed])

  // Reconcile local state when server catches up to our last write
  useEffect(() => {
    if (localClubs !== null && lastSyncedKeyRef.current === serverKey) return
    if (serverKey !== lastSyncedKeyRef.current) {
      lastSyncedKeyRef.current = serverKey
      setLocalClubs(null)
    }
  }, [serverKey, localClubs])

  const myClubs = localClubs ?? serverClubs
  const myShots = myClubs.length

  const save = useCallback(async (clubs: string[]) => {
    if (!roundId || !user || !hole) return
    setSaving(true)
    setError(null)
    setLocalClubs(clubs)
    try {
      await recordShot(roundId, holeIndex, user.uid, clubs)
      lastSyncedKeyRef.current = clubs.join('|')
      if (clubs.length > 0) setLastClubUsed(clubs[clubs.length - 1])
    } catch {
      setError('Не удалось сохранить удар. Проверьте связь.')
      setLocalClubs(null)
    } finally {
      setSaving(false)
    }
  }, [roundId, user, hole, holeIndex, setLastClubUsed])

  function addShot() {
    save([...myClubs, selectedClub])
  }

  function removeShot() {
    if (myClubs.length === 0) return
    save(myClubs.slice(0, -1))
  }

  function pickClub(club: string) {
    setSelectedClub(club)
  }

  function goToHole(n: number) {
    navigate(`/round/${roundId}/hole/${n}`)
  }

  async function handleFinish() {
    if (!roundId || finishing) return
    setFinishing(true)
    setError(null)
    try {
      await finishRound(roundId)
      navigate(`/round/${roundId}/results`)
    } catch {
      setError('Не удалось завершить раунд. Попробуйте ещё раз.')
      setFinishing(false)
    }
  }

  if (!round || !hole) {
    return (
      <div className="screen items-center justify-center">
        <p className="text-on-surface-variant text-body-md">Загрузка...</p>
      </div>
    )
  }

  const totalHoles = round.totalHoles
  const currentHole = holeIndex + 1

  return (
    <div className="screen pb-6">
      <PageHeader
        title={`Лунка ${currentHole} / ${totalHoles}`}
        right={
          <button
            type="button"
            onClick={handleFinish}
            disabled={finishing}
            className="text-label-lg text-error font-semibold min-h-touch flex items-center disabled:opacity-40"
          >
            {finishing ? '...' : 'Финиш'}
          </button>
        }
      />

      <div className="bg-primary-container px-5 py-4 flex items-center justify-between">
        <div>
          <p className="text-on-primary/70 text-label-lg">Пар</p>
          <p className="font-headline font-bold text-headline-md text-on-primary">{hole.par}</p>
        </div>
        <div className="text-center">
          <p className="font-headline font-bold text-display-lg text-on-primary">{currentHole}</p>
        </div>
        <div className="text-right">
          <p className="text-on-primary/70 text-label-lg">Дист.</p>
          <p className="font-headline font-bold text-headline-md text-on-primary">{hole.distanceMeters} м</p>
        </div>
      </div>

      <div className="flex-1 flex flex-col items-center justify-center gap-6 px-5">
        <p className="text-on-surface-variant text-label-lg font-semibold uppercase tracking-wider">
          Ваши удары
        </p>
        <div className="flex items-center gap-8">
          <button
            type="button"
            onClick={removeShot}
            disabled={myShots <= 0 || saving}
            className="w-16 h-16 rounded-full bg-surface-container-high text-on-surface text-headline-lg font-bold flex items-center justify-center active:scale-95 transition-transform disabled:opacity-30"
            aria-label="Убавить удар"
          >
            −
          </button>
          <span className="font-headline font-bold text-display-lg text-on-surface w-16 text-center">
            {myShots}
          </span>
          <button
            type="button"
            onClick={addShot}
            disabled={saving}
            className="w-16 h-16 rounded-full bg-primary text-on-primary text-headline-lg font-bold flex items-center justify-center active:scale-95 transition-transform disabled:opacity-30"
            aria-label="Добавить удар"
          >
            +
          </button>
        </div>

        {/* Strokes log */}
        {myClubs.length > 0 && (
          <div className="w-full">
            <p className="text-center text-label-md text-on-surface-variant mb-1">Серия ударов</p>
            <div className="flex flex-wrap justify-center gap-1.5">
              {myClubs.map((c, i) => (
                <span
                  key={i}
                  className="px-2 py-0.5 rounded-full bg-surface-container text-on-surface-variant text-label-md font-semibold"
                >
                  {i + 1}. {CLUB_ABBREV[c] ?? c}
                </span>
              ))}
            </div>
          </div>
        )}

        {error && (
          <p className="text-center text-label-lg text-error">{error}</p>
        )}
      </div>

      <div className="px-5 space-y-2">
        <p className="text-label-lg text-on-surface-variant font-semibold uppercase tracking-wider">
          Клюшка для следующего удара
        </p>
        <div className="flex gap-2 overflow-x-auto pb-2 -mx-5 px-5">
          {DEFAULT_CLUBS.map(club => (
            <ClubChip
              key={club}
              club={club}
              selected={selectedClub === club}
              onSelect={pickClub}
            />
          ))}
        </div>
      </div>

      <div className="flex gap-3 px-5 mt-4">
        <Button
          variant="secondary"
          disabled={currentHole === 1}
          onClick={() => goToHole(currentHole - 1)}
          className="w-auto flex-1"
        >
          ← Пред.
        </Button>
        {currentHole < totalHoles ? (
          <Button onClick={() => goToHole(currentHole + 1)} className="flex-1">
            След. →
          </Button>
        ) : (
          <Button
            onClick={handleFinish}
            disabled={finishing}
            className="flex-1 bg-tertiary-container text-on-tertiary"
          >
            {finishing ? 'Завершаем...' : 'Завершить раунд'}
          </Button>
        )}
      </div>
    </div>
  )
}
