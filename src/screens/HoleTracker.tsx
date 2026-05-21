import { useState, useEffect, useCallback, useMemo } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { Trophy, Flag, ChevronLeft, ChevronRight, Minus, Plus, WifiOff } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { useProfile } from '../hooks/useProfile'
import { useAppStore } from '../store/useAppStore'
import { subscribeToRound, finishRound, updateHoleConfig } from '../services/rounds'
import { recordShotQueued, getPendingShot, pendingCountForRound } from '../services/shotQueue'
import type { Round } from '../types'
import { getHoleClubs, getBagFromUser, enabledBagClubs, getClubLabel, DEFAULT_BAG, TEE_LABELS } from '../types'
import { ClubChip } from '../components/ui/ClubChip'
import { Button } from '../components/ui/Button'
import { Avatar } from '../components/ui/Avatar'
import { ConfirmDialog } from '../components/ui/ConfirmDialog'
import { PageHeader } from '../components/layout/PageHeader'
import { trapTab, useDialogA11y } from '../hooks/useDialogA11y'

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
  const [loadError, setLoadError] = useState<string | null>(null)
  const [finishing, setFinishing] = useState(false)
  const [showFinishConfirm, setShowFinishConfirm] = useState(false)
  const [showHoleEditor, setShowHoleEditor] = useState(false)
  const [savingHole, setSavingHole] = useState(false)

  // Active player whose shots we're editing — defaults to self
  const [activeUserId, setActiveUserId] = useState<string>('')

  // Optimistic overlay, tagged with the slot (hole + player) it belongs to and
  // the server value we're waiting to see echoed back. Slot-tagging stops an
  // in-flight save for one player bleeding into another when the host switches
  // players mid-save; `awaitingKey` stops an intermediate snapshot from rolling
  // the counter backwards when several taps overlap.
  const [optimistic, setOptimistic] = useState<{
    slot: string
    clubs: string[]
    awaitingKey: string
  } | null>(null)

  const [selectedClub, setSelectedClub] = useState<string>(lastClubUsed)

  useEffect(() => {
    if (!roundId) return
    return subscribeToRound(roundId, setRound, () => {
      setLoadError('Не удалось загрузить раунд. Проверьте связь.')
    })
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
  const isHost = !!round && !!user && round.hostId === user.uid

  const serverClubs = (hole && activeUserId) ? getHoleClubs(hole.shots[activeUserId]) : []
  const serverKey = serverClubs.join('|')
  const slotKey = `${holeIndex}:${activeUserId}`

  // Reset the club picker default when navigating to a new hole or switching
  // player. The optimistic overlay is slot-tagged so it needs no reset here —
  // it only renders for its own slot and is cleared by the reconcile effect.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- resets the picker default on hole/player change
    setSelectedClub(lastClubUsed)
  }, [holeIndex, activeUserId, lastClubUsed])

  // Snap selected club to first available if outside the picker
  useEffect(() => {
    if (!pickerClubs.some(c => c.id === selectedClub)) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- recovers from an invalid selected-club id after the user's bag changes (e.g. they disabled the currently-selected club in MyBag)
      setSelectedClub(pickerClubs[0]?.id ?? 'Driver')
    }
  }, [pickerClubs, selectedClub])

  // Show the optimistic overlay only while it's "ahead" of the server: same
  // slot, and the server hasn't yet echoed the value we wrote (awaitingKey).
  // Derived during render (not cleared via an effect) so an intermediate
  // snapshot from overlapping taps can't roll the counter back — the overlay
  // simply stops showing once the server matches our latest write. A leftover
  // overlay object is harmless: the next save overwrites it.
  // A shot recorded offline lives in the local queue until it syncs. Surface
  // it so it survives a reload (the server snapshot won't have it yet) and so
  // the user sees their count instead of a "reset".
  const pendingClubs =
    roundId && activeUserId ? getPendingShot(roundId, holeIndex, activeUserId)?.clubs : undefined
  const myClubs =
    optimistic && optimistic.slot === slotKey && serverKey !== optimistic.awaitingKey
      ? optimistic.clubs
      : pendingClubs ?? serverClubs
  const myShots = myClubs.length
  const isSelf = activeUserId === user?.uid
  const hasQueued = !!roundId && pendingCountForRound(roundId) > 0

  const save = useCallback(async (clubs: string[]) => {
    if (!roundId || !activeUserId || !hole) return
    const slot = `${holeIndex}:${activeUserId}`
    const targetUid = activeUserId
    setSaving(true)
    setError(null)
    setOptimistic({ slot, clubs, awaitingKey: clubs.join('|') })
    try {
      // Durable: queues locally then tries to sync. Offline / transient
      // failures stay queued (no rollback) and flush when connectivity returns.
      await recordShotQueued(roundId, holeIndex, targetUid, clubs)
      if (targetUid === user?.uid && clubs.length > 0) setLastClubUsed(clubs[clubs.length - 1])
    } catch {
      // Permanent rejection (e.g. round not active) — roll back this slot.
      setError('Не удалось сохранить удар.')
      setOptimistic(prev => (prev && prev.slot === slot ? null : prev))
    } finally {
      setSaving(false)
    }
  }, [roundId, activeUserId, hole, holeIndex, user, setLastClubUsed])

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
      <div className="screen items-center justify-center px-8 text-center gap-4">
        {loadError ? (
          <>
            <p className="text-error text-body-md">{loadError}</p>
            <Button variant="secondary" onClick={() => navigate('/home', { replace: true })}>
              На главную
            </Button>
          </>
        ) : (
          <p className="text-on-surface-variant text-body-md">Загрузка...</p>
        )}
      </div>
    )
  }

  const totalHoles = round.totalHoles
  const currentHole = holeIndex + 1

  return (
    <div
      className="screen"
      style={{ paddingBottom: 'max(1.5rem, env(safe-area-inset-bottom))' }}
    >
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
        {isHost ? (
          <button
            type="button"
            onClick={() => setShowHoleEditor(true)}
            className="text-left -m-2 p-2 rounded-md active:bg-on-primary/10 transition-colors"
            aria-label={`Изменить пар лунки (сейчас ${hole.par})`}
          >
            <p className="text-on-primary/70 text-label-lg">Пар</p>
            <p className="font-headline font-bold text-headline-md text-on-primary underline-offset-4 decoration-on-primary/40 decoration-dotted underline">
              {hole.par}
            </p>
          </button>
        ) : (
          <div>
            <p className="text-on-primary/70 text-label-lg">Пар</p>
            <p className="font-headline font-bold text-headline-md text-on-primary">{hole.par}</p>
          </div>
        )}
        <div className="text-center">
          <p className="font-headline font-bold text-display-lg text-on-primary">{currentHole}</p>
        </div>
        {isHost ? (
          <button
            type="button"
            onClick={() => setShowHoleEditor(true)}
            className="text-right -m-2 p-2 rounded-md active:bg-on-primary/10 transition-colors"
            aria-label={`Изменить дистанцию лунки (сейчас ${hole.distanceMeters} метров)`}
          >
            <p className="text-on-primary/70 text-label-lg">Дист.</p>
            <div className="flex items-center justify-end gap-2">
              <p className="font-headline font-bold text-headline-md text-on-primary underline-offset-4 decoration-on-primary/40 decoration-dotted underline">
                {hole.distanceMeters} м
              </p>
              {round.tee && (
                <span
                  aria-label={`Тии: ${TEE_LABELS[round.tee].label}`}
                  className="w-5 h-5 rounded-full border border-on-primary/30 shrink-0"
                  style={{ backgroundColor: TEE_LABELS[round.tee].bg }}
                  title={TEE_LABELS[round.tee].label}
                />
              )}
            </div>
          </button>
        ) : (
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
        )}
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
        <div className="flex flex-col items-center gap-3">
          <div className="flex items-center gap-10">
            <button
              type="button"
              onClick={removeShot}
              disabled={myShots <= 0 || saving}
              className="w-16 h-16 rounded-xl border-2 border-primary text-primary bg-transparent flex items-center justify-center active:scale-90 transition-all disabled:opacity-30 hover:bg-primary hover:text-on-primary"
              aria-label="Убавить удар"
            >
              <Minus size={28} strokeWidth={2} />
            </button>
            <span className="font-headline font-bold text-[64px] leading-none text-primary text-center tabular-nums w-20 h-16 flex items-center justify-center -translate-y-2">
              {myShots}
            </span>
            <button
              type="button"
              onClick={addShot}
              disabled={saving}
              className="w-16 h-16 rounded-xl bg-primary text-on-primary flex items-center justify-center active:scale-90 transition-all disabled:opacity-30 hover:bg-primary-container"
              aria-label="Добавить удар"
            >
              <Plus size={28} strokeWidth={2} />
            </button>
          </div>
          <span className="text-label-md text-on-surface-variant uppercase tracking-[0.2em] font-semibold">
            Удары
          </span>
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

        {hasQueued && (
          <p className="text-center text-label-md text-on-surface-variant inline-flex items-center justify-center gap-1.5 w-full">
            <WifiOff size={14} strokeWidth={1.75} />
            Нет сети — удары сохранятся автоматически
          </p>
        )}
      </div>

      <div className="px-5 space-y-2">
        <p className="text-label-lg text-on-surface-variant font-semibold uppercase tracking-wider text-center">
          Выбор клюшки
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
            disabled={!isHost || finishing}
            className="flex-1 uppercase tracking-wider"
          >
            {isHost ? 'Закончить игру' : 'Завершит хост'}
          </Button>
        )}
      </div>

      {isHost && currentHole < totalHoles && (
        <div className="px-5 mt-3">
          <Button
            variant="secondary"
            icon={Flag}
            onClick={requestFinish}
            disabled={finishing}
            className="uppercase tracking-wider"
          >
            Закончить игру досрочно
          </Button>
        </div>
      )}

      <ConfirmDialog
        open={showFinishConfirm}
        title="Закончить игру?"
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

      {showHoleEditor && (
        <HoleEditorDialog
          holeNumber={currentHole}
          currentPar={hole.par}
          currentDistance={hole.distanceMeters}
          saving={savingHole}
          onSave={async patch => {
            setSavingHole(true)
            setError(null)
            try {
              await updateHoleConfig(roundId!, holeIndex, patch)
              setShowHoleEditor(false)
            } catch {
              setError('Не удалось сохранить параметры лунки.')
            } finally {
              setSavingHole(false)
            }
          }}
          onClose={() => !savingHole && setShowHoleEditor(false)}
        />
      )}
    </div>
  )
}

interface HoleEditorDialogProps {
  holeNumber: number
  currentPar: 3 | 4 | 5
  currentDistance: number
  saving: boolean
  onSave: (patch: { par?: 3 | 4 | 5; distanceMeters?: number }) => void | Promise<void>
  onClose: () => void
}

function HoleEditorDialog({
  holeNumber,
  currentPar,
  currentDistance,
  saving,
  onSave,
  onClose,
}: HoleEditorDialogProps) {
  const [par, setPar] = useState<3 | 4 | 5>(currentPar)
  const [distance, setDistance] = useState<string>(String(currentDistance))
  const [validationError, setValidationError] = useState<string | null>(null)
  const dialogRef = useDialogA11y(true)

  // Escape closes the dialog (unless a save is in flight) — matches
  // ConfirmDialog/ShareDialog behaviour.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape' && !saving) onClose()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [saving, onClose])

  function handleSave() {
    const parsed = Number(distance)
    if (!Number.isFinite(parsed) || parsed < 50 || parsed > 700) {
      setValidationError('Дистанция должна быть 50–700 метров')
      return
    }
    setValidationError(null)
    const patch: { par?: 3 | 4 | 5; distanceMeters?: number } = {}
    if (par !== currentPar) patch.par = par
    if (Math.round(parsed) !== currentDistance) patch.distanceMeters = Math.round(parsed)
    if (Object.keys(patch).length === 0) {
      onClose()
      return
    }
    onSave(patch)
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="hole-editor-title"
      className="fixed inset-0 z-[100] bg-on-surface/40 flex items-end sm:items-center justify-center px-3 sm:px-5"
      onClick={onClose}
    >
      <div
        ref={dialogRef}
        className="bg-surface-container-lowest rounded-t-xl sm:rounded-xl max-w-sm w-full p-5 space-y-5 shadow-elevated focus:outline-none"
        onClick={e => e.stopPropagation()}
        onKeyDown={trapTab}
      >
        <div>
          <h2
            id="hole-editor-title"
            className="font-headline font-bold text-title-lg text-on-surface tracking-tight"
          >
            Параметры лунки {holeNumber}
          </h2>
          <p className="text-label-md text-on-surface-variant mt-1">
            Подгоните под реальное поле — изменение видно всем игрокам.
          </p>
        </div>

        <div>
          <p className="text-label-md text-on-surface-variant uppercase tracking-wider font-semibold mb-2">
            Пар
          </p>
          <div className="grid grid-cols-3 gap-2">
            {([3, 4, 5] as const).map(p => {
              const selected = par === p
              return (
                <button
                  key={p}
                  type="button"
                  disabled={saving}
                  onClick={() => setPar(p)}
                  className={`h-16 rounded-xl border-2 transition-colors flex items-center justify-center disabled:opacity-50 ${
                    selected
                      ? 'border-primary bg-primary text-on-primary'
                      : 'border-outline-variant text-on-surface bg-surface-container-lowest hover:border-primary'
                  }`}
                >
                  <span className="font-headline font-bold text-display-lg leading-none -translate-y-[3px]">
                    {p}
                  </span>
                </button>
              )
            })}
          </div>
        </div>

        <div>
          <label
            htmlFor="hole-distance-input"
            className="text-label-md text-on-surface-variant uppercase tracking-wider font-semibold mb-2 block"
          >
            Дистанция, метров
          </label>
          <input
            id="hole-distance-input"
            type="number"
            inputMode="numeric"
            min={50}
            max={700}
            step={1}
            value={distance}
            disabled={saving}
            onChange={e => {
              setDistance(e.target.value)
              if (validationError) setValidationError(null)
            }}
            className="w-full h-14 px-4 bg-surface-container-low rounded-md text-headline-md font-headline font-bold border border-outline-variant/30 focus:border-primary focus:outline-none disabled:opacity-50 tabular-nums"
          />
          {validationError && (
            <p className="text-label-md text-error mt-1">{validationError}</p>
          )}
        </div>

        <div className="flex gap-2 pt-1">
          <Button
            variant="secondary"
            onClick={onClose}
            disabled={saving}
            className="flex-1 uppercase tracking-wider"
            data-autofocus
          >
            Отмена
          </Button>
          <Button
            onClick={handleSave}
            disabled={saving}
            className="flex-1 uppercase tracking-wider"
          >
            {saving ? 'Сохраняем...' : 'Сохранить'}
          </Button>
        </div>
      </div>
    </div>
  )
}
