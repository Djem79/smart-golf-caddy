import { useState, useEffect, useCallback } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { useGeolocation } from '../hooks/useGeolocation'
import { useAppStore } from '../store/useAppStore'
import { subscribeToRound, recordShot, finishRound } from '../services/rounds'
import { haversineMetres } from '../services/distance'
import type { Round } from '../types'
import { DEFAULT_CLUBS } from '../types'
import { ClubChip } from '../components/ui/ClubChip'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'

export function HoleTracker() {
  const { roundId, holeNumber } = useParams<{ roundId: string; holeNumber: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const { lat, lng } = useGeolocation()
  const { lastClubUsed, setLastClubUsed } = useAppStore()

  const holeIndex = parseInt(holeNumber ?? '1', 10) - 1
  const [round, setRound] = useState<Round | null>(null)
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (!roundId) return
    return subscribeToRound(roundId, setRound)
  }, [roundId])

  const hole = round?.holes[holeIndex]
  const myShots = (hole && user) ? (hole.shots[user.uid]?.count ?? 0) : 0
  const myClub = (hole && user) ? (hole.shots[user.uid]?.club ?? lastClubUsed) : lastClubUsed

  // GPS placeholder: until we have real per-hole pin coordinates, show distance to a small offset
  // (Plan 2 will integrate real course hole pin data from Golfbert API)
  const distanceM = hole && lat != null && lng != null
    ? Math.round(haversineMetres(lat, lng, lat + 0.001, lng + 0.001))
    : null

  const save = useCallback(async (count: number, club: string) => {
    if (!roundId || !user || !hole) return
    setSaving(true)
    try {
      await recordShot(roundId, holeIndex, user.uid, count, club)
      setLastClubUsed(club)
    } finally {
      setSaving(false)
    }
  }, [roundId, user, hole, holeIndex, setLastClubUsed])

  function changeShots(delta: number) {
    const next = Math.max(1, myShots + delta)
    save(next, myClub)
  }

  function changeClub(club: string) {
    save(myShots === 0 ? 1 : myShots, club)
  }

  function goToHole(n: number) {
    navigate(`/round/${roundId}/hole/${n}`)
  }

  async function handleFinish() {
    if (!roundId) return
    await finishRound(roundId)
    navigate(`/round/${roundId}/results`)
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
            onClick={handleFinish}
            className="text-label-lg text-error font-semibold min-h-touch flex items-center"
          >
            Финиш
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

      {distanceM !== null && (
        <div className="mx-5 mt-3 px-4 py-2 bg-tertiary-container rounded-lg flex items-center gap-2">
          <span className="text-on-tertiary text-label-lg">📍</span>
          <span className="text-on-tertiary text-label-lg font-semibold">
            ~{distanceM} м до поля
          </span>
        </div>
      )}

      <div className="flex-1 flex flex-col items-center justify-center gap-6 px-5">
        <p className="text-on-surface-variant text-label-lg font-semibold uppercase tracking-wider">
          Ваши удары
        </p>
        <div className="flex items-center gap-8">
          <button
            type="button"
            onClick={() => changeShots(-1)}
            disabled={myShots <= 1 || saving}
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
            onClick={() => changeShots(+1)}
            disabled={saving}
            className="w-16 h-16 rounded-full bg-primary text-on-primary text-headline-lg font-bold flex items-center justify-center active:scale-95 transition-transform"
            aria-label="Добавить удар"
          >
            +
          </button>
        </div>
      </div>

      <div className="px-5 space-y-2">
        <p className="text-label-lg text-on-surface-variant font-semibold uppercase tracking-wider">
          Клюшка
        </p>
        <div className="flex gap-2 overflow-x-auto pb-2 -mx-5 px-5">
          {DEFAULT_CLUBS.map(club => (
            <ClubChip
              key={club}
              club={club}
              selected={myClub === club}
              onSelect={changeClub}
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
          <Button onClick={handleFinish} className="flex-1 bg-tertiary-container text-on-tertiary">
            Завершить раунд
          </Button>
        )}
      </div>
    </div>
  )
}
