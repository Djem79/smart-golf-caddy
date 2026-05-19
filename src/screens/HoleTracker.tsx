import { useState, useEffect, useCallback, useMemo, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { Trophy, Flag, ChevronLeft, ChevronRight, Minus, Plus } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { useProfile } from '../hooks/useProfile'
import { useAppStore } from '../store/useAppStore'
import { subscribeToRound, recordShot, finishRound } from '../services/rounds'
import type { Round } from '../types'
import { getHoleClubs, getBagFromUser, enabledBagClubs, getClubLabel, DEFAULT_BAG, TEE_LABELS } from '../types'
import { ClubChip } from '../components/ui/ClubChip'
import { Button } from '../components/ui/Button'
import { Avatar } from '../components/ui/Avatar'
import { ConfirmDialog } from '../components/ui/ConfirmDialog'
import { PageHeader } from '../components/layout/PageHeader'

export function HoleTracker() {
  const { roundId, holeNumber } = useParams<{ roundId: string; holeNumber: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const { profile } = useProfile()
  const { lastClubUsed, setLastClubUsed } = useAppStore()

  const pickerClubs = useMemo(() => {
    const enabled = enabledBagClubs(getBagFromUser(profile))
    return enabled.length > 0 ? enabled : DEFAULT_BAG
  }, [profile])

  // Full bag (incl. disabled / custom clubs) — used to resolve display labels
  // for clubs referenced in already-recorded shots that may be disabled now.
  const fullBag = useMemo(() => getBagFromUser(profile), [profile])

  const holeIndex = parseInt(holeNumber ?? '1', 10) - 1
  const [round, setRound] = useState<Round | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [finishing, setFinishing] = useState(false)
  const [showFinishConfirm, setShowFinishConfirm] = useState(false)

  // Active player whose shots we're editing — defaults to self
  const [activeUserId, setActiveUserId] = useState<string>('')

  const [localClubs, setLocalClubs] = useState<string[] | null>(null)
  const lastSyncedKeyRef = useRef<string | null>(null)

  const [selectedClub, setSelectedClub] = useState<string>(lastClubUsed)

  useEffect(() => {
    if (!roundId) return
    return subscribeToRound(roundId, setRound)
  }, [roundId])

  // Initialize active player to self once we have user + round
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- one-shot initialisation: copy auth uid into activeUserId once it becomes available
    if (!activeUserId && user) setActiveUserId(user.uid)
  }, [activeUserId, user])

  // If round status went back to 'lobby' (host left etc.) bounce to lobby; if finished — to results
  useEffect(() => {
    if (!roundId || !round) return
    if (round.status === 'lobby') {
      navigate(`/round/${roundId}/lobby`, { replace: true })
    } else if (round.status === 'finished') {
      navigate(`/round/${roundId}/results`, { replace: true })
    }
  }, [round, roundId, navigate])

  const hole = round?.holes[holeIndex]
  const playerIds = round?.playerIds ?? []
  const isMultiplayer = playerIds.length > 1

  const serverClubs = (hole && activeUserId) ? getHoleClubs(hole.shots[activeUserId]) : []
  const serverKey = serverClubs.join('|')

  // Reset optimistic state when navigating to a new hole or switching player
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- discards stale per-hole local state when the user navigates between holes or switches the active player; safe because it only runs on those dep transitions
    setLocalClubs(null)
    lastSyncedKeyRef.current = null
    setSelectedClub(lastClubUsed)
  }, [holeIndex, activeUserId, lastClubUsed])

  // Snap selected club to first available if outside the picker
  useEffect(() => {
    if (!pickerClubs.some(c => c.id === selectedClub)) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- recovers from an invalid selected-club id after the user's bag changes (e.g. they disabled the currently-selected club in MyBag)
      setSelectedClub(pickerClubs[0]?.id ?? 'Driver')
    }
  }, [pickerClubs, selectedClub])

  // Reconcile local state when the server catches up to our last write
  useEffect(() => {
    if (localClubs !== null && lastSyncedKeyRef.current === serverKey) return
    if (serverKey !== lastSyncedKeyRef.current) {
      lastSyncedKeyRef.current = serverKey
      setLocalClubs(null)
    }
  }, [serverKey, localClubs])

  const myClubs = localClubs ?? serverClubs
  const myShots = myClubs.length
  const isSelf = activeUserId === user?.uid

  const save = useCallback(async (clubs: string[]) => {
    if (!roundId || !activeUserId || !hole) return
    setSaving(true)
    setError(null)
    setLocalClubs(clubs)
    try {
      await recordShot(roundId, holeIndex, activeUserId, clubs)
      lastSyncedKeyRef.current = clubs.join('|')
      // Only update lastClubUsed if I'm recording my own shot — don't track others' clubs in my preferences
      if (isSelf && clubs.length > 0) setLastClubUsed(clubs[clubs.length - 1])
    } catch {
      setError('Не удалось сохранить удар. Проверьте связь.')
      setLocalClubs(null)
    } finally {
      setSaving(false)
    }
  }, [roundId, activeUserId, hole, holeIndex, isSelf, setLastClubUsed])

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
  function requestFinish() {
    setShowFinishConfirm(true)
  }
  async function confirmFinish() {
    if (!roundId || finishing) return
    setFinishing(true)
    setError(null)
    try {
      await finishRound(roundId)
      navigate(`/round/${roundId}/results`)
    } catch {
      setError('Не удалось завершить раунд. Попробуйте ещё раз.')
      setFinishing(false)
      setShowFinishConfirm(false)
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
            onClick={() => navigate(`/round/${roundId}/leaderboard`)}
            aria-label="Турнирная таблица"
            className="min-h-touch min-w-touch flex items-center justify-center text-on-surface rounded-full active:bg-surface-container-high/60 transition-colors"
          >
            <Trophy size={22} strokeWidth={1.75} />
          </button>
        }
      />

      <div className="bg-primary-container px-5 py-4 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <div>
            <p className="text-on-primary/70 text-label-lg">Пар</p>
            <p className="font-headline font-bold text-headline-md text-on-primary">{hole.par}</p>
          </div>
        </div>
        <div className="text-center">
          <p className="font-headline font-bold text-display-lg text-on-primary">{currentHole}</p>
        </div>
        <div className="text-right">
          <p className="text-on-primary/70 text-label-lg">Дист.</p>
          <div className="flex items-center justify-end gap-2">
            <p className="font-headline font-bold text-headline-md text-on-primary">{hole.distanceMeters} м</p>
            {round.tee && (
              <span
                aria-label={`Тии: ${TEE_LABELS[round.tee].label}`}
                className="w-5 h-5 rounded-full border border-on-primary/30 shrink-0"
                style={{ backgroundColor: TEE_LABELS[round.tee].bg }}
                title={TEE_LABELS[round.tee].label}
              />
            )}
          </div>
        </div>
      </div>

      {/* Player switcher (only in multiplayer) */}
      {isMultiplayer && (
        <div className="px-5 pt-3">
          <p className="text-label-md text-on-surface-variant uppercase tracking-wider mb-2">
            Игрок (тап для переключения)
          </p>
          <div className="flex gap-2 overflow-x-auto pb-1 -mx-5 px-5">
            {playerIds.map(uid => {
              const p = round.players[uid]
              if (!p) return null
              const active = uid === activeUserId
              const count = hole.shots[uid]?.count ?? 0
              const isMe = uid === user?.uid
              return (
                <button
                  key={uid}
                  type="button"
                  onClick={() => setActiveUserId(uid)}
                  className={`shrink-0 flex items-center gap-2 px-3 py-2 rounded-full border transition-colors min-h-touch ${
                    active
                      ? 'bg-primary text-on-primary border-primary'
                      : 'bg-surface-container-lowest text-on-surface border-outline-variant/60 hover:border-outline-variant'
                  }`}
                >
                  <Avatar src={p.avatar} name={p.name} size={24} />
                  <span className="font-semibold text-label-lg truncate max-w-[100px]">
                    {isMe ? 'Вы' : p.name}
                  </span>
                  <span className={`text-label-lg font-bold tabular-nums ${active ? 'text-on-primary' : 'text-primary'}`}>
                    {count}
                  </span>
                </button>
              )
            })}
          </div>
        </div>
      )}

      <div className="flex-1 flex flex-col items-center justify-center gap-6 px-5 py-4">
        <p className="text-on-surface-variant text-label-lg font-semibold uppercase tracking-wider">
          {isSelf || !isMultiplayer
            ? 'Ваши удары'
            : `Удары: ${round.players[activeUserId]?.name ?? '—'}`}
        </p>
        <div className="flex items-center gap-8">
          <button
            type="button"
            onClick={removeShot}
            disabled={myShots <= 0 || saving}
            className="w-16 h-16 rounded-full bg-surface-container-high text-on-surface flex items-center justify-center active:scale-95 transition-transform disabled:opacity-30 shadow-card"
            aria-label="Убавить удар"
          >
            <Minus size={26} strokeWidth={2} />
          </button>
          <span className="font-headline font-bold text-display-lg text-on-surface w-16 text-center tabular-nums">
            {myShots}
          </span>
          <button
            type="button"
            onClick={addShot}
            disabled={saving}
            className="w-16 h-16 rounded-full bg-primary text-on-primary flex items-center justify-center active:scale-95 transition-transform disabled:opacity-30 shadow-card"
            aria-label="Добавить удар"
          >
            <Plus size={26} strokeWidth={2} />
          </button>
        </div>

        {myClubs.length > 0 && (
          <div className="w-full">
            <p className="text-center text-label-md text-on-surface-variant mb-1">Серия ударов</p>
            <div className="flex flex-wrap justify-center gap-1.5">
              {myClubs.map((c, i) => (
                <span
                  key={i}
                  className="px-2 py-0.5 rounded-full bg-surface-container text-on-surface-variant text-label-md font-semibold"
                >
                  {i + 1}. {getClubLabel(c, fullBag)}
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
          {pickerClubs.map(c => (
            <ClubChip
              key={c.id}
              club={c.id}
              label={getClubLabel(c.id, fullBag)}
              selected={selectedClub === c.id}
              onSelect={pickClub}
            />
          ))}
        </div>
      </div>

      <div className="flex gap-3 px-5 mt-4">
        <Button
          variant="secondary"
          icon={ChevronLeft}
          disabled={currentHole === 1}
          onClick={() => goToHole(currentHole - 1)}
          className="w-auto flex-1"
        >
          Пред.
        </Button>
        {currentHole < totalHoles ? (
          <Button iconRight={ChevronRight} onClick={() => goToHole(currentHole + 1)} className="flex-1">
            Дальше
          </Button>
        ) : (
          <Button
            icon={Flag}
            onClick={requestFinish}
            disabled={finishing}
            className="flex-1"
          >
            Завершить раунд
          </Button>
        )}
      </div>

      {currentHole < totalHoles && (
        <button
          type="button"
          onClick={requestFinish}
          disabled={finishing}
          className="mt-3 mx-auto text-label-lg text-on-surface-variant font-semibold underline min-h-touch px-3 disabled:opacity-40"
        >
          Завершить раунд досрочно
        </button>
      )}

      <ConfirmDialog
        open={showFinishConfirm}
        title="Завершить раунд?"
        body={
          currentHole < totalHoles
            ? `Вы прошли ${currentHole - 1} из ${totalHoles} лунок. Пройденные удары попадут в итоги, незавершённые лунки — без ударов.`
            : 'Раунд будет записан в историю. Изменить удары после этого нельзя.'
        }
        confirmLabel="Завершить"
        cancelLabel="Продолжить"
        loading={finishing}
        onConfirm={confirmFinish}
        onCancel={() => setShowFinishConfirm(false)}
      />
    </div>
  )
}
