import { useEffect, useMemo, useState } from 'react'
import { useAuth } from '../hooks/useAuth'
import { useProfile } from '../hooks/useProfile'
import { updateBag, updateUnits } from '../services/users'
import {
  CLUB_ABBREV, CLUB_GROUPS, DEFAULT_BAG, getBagFromUser, getClubCategory,
  metersToYards, yardsToMeters,
} from '../types'
import type { BagClub, ClubCategory, DistanceUnit } from '../types'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'

const TOTAL_SLOTS = 14

export function MyBag() {
  const { user } = useAuth()
  const { profile, loading } = useProfile()
  const [bag, setBag] = useState<BagClub[]>(DEFAULT_BAG)
  const [units, setUnits] = useState<DistanceUnit>('m')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [adding, setAdding] = useState<ClubCategory | null>(null)

  useEffect(() => {
    if (loading) return
    setBag(getBagFromUser(profile))
    setUnits(profile?.units ?? 'm')
  }, [profile, loading])

  const enabledCount = useMemo(() => bag.filter(c => c.enabled).length, [bag])
  const progressPct = Math.min(100, Math.round((enabledCount / TOTAL_SLOTS) * 100))

  async function persistBag(next: BagClub[]) {
    if (!user) return
    setBag(next)
    setSaving(true)
    setError(null)
    try {
      await updateBag(user.uid, next)
    } catch {
      setError('Не удалось сохранить изменения')
    } finally {
      setSaving(false)
    }
  }

  async function toggle(id: string) {
    await persistBag(bag.map(c => c.id === id ? { ...c, enabled: !c.enabled } : c))
  }

  async function setName(id: string, name: string) {
    const trimmed = name.trim()
    const club = bag.find(c => c.id === id)
    if (!club || (club.customName ?? '') === trimmed) return
    await persistBag(bag.map(c => c.id === id ? { ...c, customName: trimmed || undefined } : c))
  }

  async function setDistance(id: string, raw: string) {
    const num = parseInt(raw, 10)
    if (Number.isNaN(num) || num < 0) return
    const meters = units === 'yd' ? yardsToMeters(num) : num
    const club = bag.find(c => c.id === id)
    if (!club || club.distanceMeters === meters) return
    await persistBag(bag.map(c => c.id === id ? { ...c, distanceMeters: meters } : c))
  }

  async function changeUnits(u: DistanceUnit) {
    if (u === units) return
    setUnits(u)
    if (!user) return
    try { await updateUnits(user.uid, u) } catch { /* non-critical */ }
  }

  async function addCustomClub(category: ClubCategory, name: string, distance: number) {
    const trimmed = name.trim()
    if (!trimmed) return
    const meters = units === 'yd' ? yardsToMeters(distance) : distance
    const id = `custom-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`
    const newClub: BagClub = {
      id, customName: trimmed, distanceMeters: meters,
      enabled: true, category, custom: true,
    }
    await persistBag([...bag, newClub])
    setAdding(null)
  }

  async function deleteClub(id: string) {
    await persistBag(bag.filter(c => c.id !== id))
  }

  // Swap a club with the previous/next club in the same category.
  // The bag array is the order of truth — HoleTracker's picker reads
  // enabledBagClubs(bag) which preserves array order.
  async function moveClub(id: string, direction: 'up' | 'down') {
    const idx = bag.findIndex(c => c.id === id)
    if (idx === -1) return
    const category = getClubCategory(bag[idx])

    // Find the neighbour in the same category, scanning the bag in the
    // requested direction. Skipping clubs of other categories keeps the
    // section visually intact (groups in MyBag stay coherent).
    let neighbour = -1
    if (direction === 'up') {
      for (let i = idx - 1; i >= 0; i--) {
        if (getClubCategory(bag[i]) === category) { neighbour = i; break }
      }
    } else {
      for (let i = idx + 1; i < bag.length; i++) {
        if (getClubCategory(bag[i]) === category) { neighbour = i; break }
      }
    }
    if (neighbour === -1) return

    const next = [...bag]
    ;[next[idx], next[neighbour]] = [next[neighbour], next[idx]]
    await persistBag(next)
  }

  function distanceValue(club: BagClub): number {
    if (getClubCategory(club) === 'putter') return 0
    return units === 'yd' ? metersToYards(club.distanceMeters) : club.distanceMeters
  }

  function clubsInGroup(category: ClubCategory): BagClub[] {
    return bag.filter(c => getClubCategory(c) === category)
  }

  return (
    <div className="screen pb-20">
      <PageHeader
        title="Моя сумка"
        right={
          saving
            ? <span className="text-label-md text-on-surface-variant min-h-touch flex items-center">Сохранение...</span>
            : null
        }
      />

      <div className="flex-1 px-5 pt-5 space-y-5 overflow-y-auto">
        {/* Counter */}
        <Card>
          <div className="flex items-end justify-between mb-3">
            <div>
              <h2 className="font-headline font-bold text-headline-md text-primary">Состав сумки</h2>
              <p className="text-label-md text-on-surface-variant mt-0.5">До 14 клюшек по правилам</p>
            </div>
            <div className="text-right shrink-0">
              <span className="font-headline font-bold text-display-lg text-primary">
                {enabledCount}
                <span className="text-title-lg text-on-surface-variant">/{TOTAL_SLOTS}</span>
              </span>
            </div>
          </div>
          <div className="w-full h-2 bg-surface-container-high rounded-full overflow-hidden">
            <div
              className="h-full bg-primary rounded-full transition-all duration-500"
              style={{ width: `${progressPct}%` }}
            />
          </div>
          {enabledCount < TOTAL_SLOTS && (
            <p className="text-label-md text-on-surface-variant text-center mt-2">
              Свободных слотов: {TOTAL_SLOTS - enabledCount}
            </p>
          )}
        </Card>

        {/* Units toggle */}
        <div className="flex justify-center">
          <div className="inline-flex p-1 bg-surface-container rounded-lg">
            {(['m', 'yd'] as const).map(u => (
              <button
                key={u}
                type="button"
                onClick={() => changeUnits(u)}
                className={`px-6 py-2 rounded-md text-label-lg font-semibold transition-colors min-h-touch ${
                  units === u
                    ? 'bg-surface-container-lowest text-primary shadow-card'
                    : 'text-on-surface-variant'
                }`}
              >
                {u === 'm' ? 'Метры' : 'Ярды'}
              </button>
            ))}
          </div>
        </div>

        {error && (
          <p className="text-center text-label-lg text-error">{error}</p>
        )}

        {/* Grouped club list */}
        {CLUB_GROUPS.map(group => {
          const clubs = clubsInGroup(group.category)
          return (
            <div key={group.category} className="space-y-2.5">
              <div className="flex items-center justify-between px-1">
                <h3 className="font-headline font-semibold text-title-lg text-on-surface">
                  {group.label}
                </h3>
                <span className="text-label-md text-on-surface-variant">
                  {clubs.filter(c => c.enabled).length}/{clubs.length}
                </span>
              </div>
              <div className="space-y-2">
                {clubs.map((club, idx) => (
                  <ClubRow
                    key={club.id}
                    club={club}
                    units={units}
                    distanceValue={distanceValue(club)}
                    isPutter={getClubCategory(club) === 'putter'}
                    onToggle={() => toggle(club.id)}
                    onSetName={(n) => setName(club.id, n)}
                    onSetDistance={(d) => setDistance(club.id, d)}
                    onDelete={club.custom ? () => deleteClub(club.id) : undefined}
                    canMoveUp={idx > 0}
                    canMoveDown={idx < clubs.length - 1}
                    onMoveUp={() => moveClub(club.id, 'up')}
                    onMoveDown={() => moveClub(club.id, 'down')}
                  />
                ))}

                {adding === group.category ? (
                  <AddClubForm
                    units={units}
                    category={group.category}
                    onAdd={addCustomClub}
                    onCancel={() => setAdding(null)}
                  />
                ) : (
                  <button
                    type="button"
                    onClick={() => setAdding(group.category)}
                    className="w-full min-h-touch flex items-center justify-center gap-2 text-label-lg font-semibold text-primary border-2 border-dashed border-outline-variant rounded-lg hover:bg-primary-container/10 transition-colors active:scale-[0.99]"
                  >
                    + Добавить клюшку
                  </button>
                )}
              </div>
            </div>
          )
        })}
      </div>

      <BottomNav />
    </div>
  )
}

interface ClubRowProps {
  club: BagClub
  units: DistanceUnit
  distanceValue: number
  isPutter: boolean
  onToggle: () => void
  onSetName: (name: string) => void
  onSetDistance: (raw: string) => void
  onDelete?: () => void
  canMoveUp: boolean
  canMoveDown: boolean
  onMoveUp: () => void
  onMoveDown: () => void
}

function ClubRow({
  club, units, distanceValue, isPutter,
  onToggle, onSetName, onSetDistance, onDelete,
  canMoveUp, canMoveDown, onMoveUp, onMoveDown,
}: ClubRowProps) {
  const displayLabel = club.custom ? (club.customName || 'Клюшка') : club.id

  return (
    <div className={`flex items-center gap-2 p-3 bg-surface-container-lowest border border-outline-variant/30 rounded-lg transition-opacity ${!club.enabled ? 'opacity-60' : ''}`}>
      <div className="flex flex-col shrink-0">
        <button
          type="button"
          onClick={onMoveUp}
          disabled={!canMoveUp}
          aria-label={`Поднять ${displayLabel} выше`}
          className="w-6 h-5 flex items-center justify-center text-on-surface-variant disabled:opacity-20 active:scale-95"
        >
          ▲
        </button>
        <button
          type="button"
          onClick={onMoveDown}
          disabled={!canMoveDown}
          aria-label={`Опустить ${displayLabel} ниже`}
          className="w-6 h-5 flex items-center justify-center text-on-surface-variant disabled:opacity-20 active:scale-95"
        >
          ▼
        </button>
      </div>
      <div className="w-11 h-11 shrink-0 rounded-md bg-secondary-container flex items-center justify-center font-headline font-bold text-label-lg text-on-surface">
        {CLUB_ABBREV[club.id] ?? (club.custom ? '✦' : club.id)}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-semibold text-label-lg text-on-surface truncate">{displayLabel}</p>
        <input
          type="text"
          placeholder={club.custom ? 'Название' : 'Модель'}
          defaultValue={club.customName ?? ''}
          onBlur={e => onSetName(e.target.value)}
          className="w-full h-7 px-0 text-label-md bg-transparent border-none text-on-surface-variant placeholder:text-on-surface-variant/50"
        />
      </div>
      {!isPutter ? (
        <div className="flex items-center bg-surface-container rounded h-10 px-2 border border-outline-variant focus-within:border-primary">
          <input
            key={`${club.id}-${units}-${club.distanceMeters}`}
            type="number"
            inputMode="numeric"
            min={0}
            max={400}
            defaultValue={distanceValue}
            onBlur={e => onSetDistance(e.target.value)}
            className="w-12 bg-transparent border-none text-right text-label-md font-semibold text-on-surface p-0"
          />
          <span className="ml-1 text-label-md text-on-surface-variant">{units === 'yd' ? 'я' : 'м'}</span>
        </div>
      ) : (
        <div className="text-label-md text-on-surface-variant w-16 text-center">—</div>
      )}
      <input
        type="checkbox"
        checked={club.enabled}
        onChange={onToggle}
        aria-label={`Включить ${displayLabel} в сумку`}
        className="w-6 h-6 accent-primary cursor-pointer shrink-0"
      />
      {onDelete && (
        <button
          type="button"
          onClick={onDelete}
          aria-label="Удалить клюшку"
          className="w-8 h-8 shrink-0 flex items-center justify-center text-error text-headline-md leading-none rounded-full hover:bg-error-container/30 transition-colors"
        >
          ×
        </button>
      )}
    </div>
  )
}

interface AddClubFormProps {
  units: DistanceUnit
  category: ClubCategory
  onAdd: (category: ClubCategory, name: string, distance: number) => void
  onCancel: () => void
}

function AddClubForm({ units, category, onAdd, onCancel }: AddClubFormProps) {
  const [name, setName] = useState('')
  const [distance, setDistance] = useState('')

  function submit() {
    const num = parseInt(distance, 10) || 0
    if (!name.trim()) return
    onAdd(category, name, num)
  }

  return (
    <div className="p-3 bg-primary-container/15 border border-primary/40 rounded-lg space-y-2">
      <div className="flex items-center gap-2">
        <input
          type="text"
          placeholder="Например: Hybrid 3"
          value={name}
          onChange={e => setName(e.target.value)}
          autoFocus
          className="flex-1 h-10 px-3 text-body-md bg-surface-container-lowest border border-outline-variant rounded focus:border-primary"
        />
        <div className="flex items-center bg-surface-container-lowest rounded h-10 px-2 border border-outline-variant focus-within:border-primary">
          <input
            type="number"
            inputMode="numeric"
            min={0}
            max={400}
            placeholder="0"
            value={distance}
            onChange={e => setDistance(e.target.value)}
            className="w-14 bg-transparent border-none text-right text-label-md font-semibold text-on-surface p-0"
          />
          <span className="ml-1 text-label-md text-on-surface-variant">{units === 'yd' ? 'я' : 'м'}</span>
        </div>
      </div>
      <div className="flex gap-2">
        <Button onClick={submit} disabled={!name.trim()} className="flex-1">
          Добавить
        </Button>
        <Button variant="secondary" onClick={onCancel} className="flex-1">
          Отмена
        </Button>
      </div>
    </div>
  )
}
