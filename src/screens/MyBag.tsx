import { useEffect, useMemo, useState } from 'react'
import { GripVertical, Sparkle } from 'lucide-react'
import {
  DndContext, PointerSensor, KeyboardSensor, TouchSensor,
  useSensor, useSensors, closestCenter,
} from '@dnd-kit/core'
import type { DragEndEvent } from '@dnd-kit/core'
import {
  SortableContext, arrayMove, sortableKeyboardCoordinates,
  useSortable, verticalListSortingStrategy,
} from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
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
    // eslint-disable-next-line react-hooks/set-state-in-effect -- sync local optimistic state with the latest Firestore profile snapshot; the alternative (useSyncExternalStore) is a larger refactor than warranted here
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
    // Insert at the end of this category's slice rather than appending to the
    // very end of the bag. The picker in HoleTracker iterates bag in order
    // (only filtering disabled), so appending to the absolute end would push
    // a new wood/iron behind the Putter row in that picker, mismatching the
    // grouped UI here.
    let insertAt = bag.length
    for (let i = bag.length - 1; i >= 0; i--) {
      if (getClubCategory(bag[i]) === category) {
        insertAt = i + 1
        break
      }
    }
    const next = [...bag.slice(0, insertAt), newClub, ...bag.slice(insertAt)]
    await persistBag(next)
    setAdding(null)
  }

  async function deleteClub(id: string) {
    await persistBag(bag.filter(c => c.id !== id))
  }

  // Drag-and-drop reorder within a single category. The bag array is the
  // order of truth — HoleTracker's picker reads enabledBagClubs(bag) which
  // preserves array order. We reorder within the category's positional
  // slice, then splice the reordered slice back into the bag.
  async function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event
    if (!over || active.id === over.id) return

    const activeIdx = bag.findIndex(c => c.id === active.id)
    const overIdx = bag.findIndex(c => c.id === over.id)
    if (activeIdx === -1 || overIdx === -1) return

    // Only allow reordering within the same category — dropping a Driver
    // into the Wedges section would confuse the grouped UI.
    const activeCat = getClubCategory(bag[activeIdx])
    const overCat = getClubCategory(bag[overIdx])
    if (activeCat !== overCat) return

    await persistBag(arrayMove(bag, activeIdx, overIdx))
  }

  // DnD sensors: pointer (mouse/stylus), touch (long-press 200ms to avoid
  // accidental drag while scrolling), keyboard (tab + space + arrows).
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 6 } }),
    useSensor(TouchSensor, { activationConstraint: { delay: 200, tolerance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  )

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

        {/* Grouped club list — wrapped in a single DndContext; each category
            gets its own SortableContext so drag is constrained per group. */}
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
        {CLUB_GROUPS.map(group => {
          const clubs = clubsInGroup(group.category)
          const ids = clubs.map(c => c.id)
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
              <SortableContext items={ids} strategy={verticalListSortingStrategy}>
              <div className="space-y-2">
                {clubs.map(club => (
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
                  />
                ))}

              </div>
              </SortableContext>

              <div className="space-y-2 mt-2">
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
        </DndContext>
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
}

function ClubRow({
  club, units, distanceValue, isPutter,
  onToggle, onSetName, onSetDistance, onDelete,
}: ClubRowProps) {
  const displayLabel = club.custom ? (club.customName || 'Клюшка') : club.id

  // useSortable wires this row into the surrounding SortableContext.
  // `setNodeRef` is the whole row; `setActivatorNodeRef` + listeners go on
  // the grip handle so other taps (checkbox / inputs) still work normally.
  const {
    attributes,
    listeners,
    setNodeRef,
    setActivatorNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: club.id })

  const style: React.CSSProperties = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.4 : (club.enabled ? 1 : 0.6),
    zIndex: isDragging ? 10 : undefined,
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      className="flex items-center gap-1.5 p-2.5 bg-surface-container-lowest border border-outline-variant/30 rounded-lg touch-manipulation"
    >
      <button
        type="button"
        ref={setActivatorNodeRef}
        aria-label={`Перетащить ${displayLabel}`}
        {...attributes}
        {...listeners}
        className="min-w-touch h-10 -mx-1 shrink-0 flex items-center justify-center text-on-surface-variant/50 cursor-grab active:cursor-grabbing touch-none select-none"
      >
        <GripVertical size={16} strokeWidth={1.75} />
      </button>
      <div className="w-10 h-10 shrink-0 rounded-md bg-secondary-container flex items-center justify-center font-headline font-bold text-on-surface px-1">
        {CLUB_ABBREV[club.id] ? (
          <span className="text-label-lg">{CLUB_ABBREV[club.id]}</span>
        ) : club.custom ? (
          club.customName && club.customName.trim().length > 0 ? (
            <span className="text-label-md leading-none truncate">
              {club.customName.trim().slice(0, 3)}
            </span>
          ) : (
            <Sparkle size={16} strokeWidth={1.75} className="text-on-surface/70" />
          )
        ) : (
          <span className="text-label-lg">{club.id}</span>
        )}
      </div>
      <div className="flex-1 min-w-0">
        <p className="font-semibold text-label-lg text-on-surface truncate">{displayLabel}</p>
        <input
          type="text"
          aria-label={`${club.custom ? 'Название' : 'Модель'} клюшки ${displayLabel}`}
          placeholder={club.custom ? 'Название' : 'Модель'}
          defaultValue={club.customName ?? ''}
          onBlur={e => onSetName(e.target.value)}
          className="w-full h-6 px-0 text-label-md bg-transparent border-none text-on-surface-variant placeholder:text-on-surface-variant/50"
        />
      </div>
      {!isPutter ? (
        <div className="flex items-center bg-surface-container rounded h-9 px-1.5 border border-outline-variant focus-within:border-primary shrink-0">
          <input
            key={`${club.id}-${units}-${club.distanceMeters}`}
            type="number"
            inputMode="numeric"
            aria-label={`Дистанция ${displayLabel}, ${units === 'yd' ? 'ярды' : 'метры'}`}
            min={0}
            max={400}
            defaultValue={distanceValue}
            onBlur={e => onSetDistance(e.target.value)}
            className="w-10 bg-transparent border-none text-right text-label-md font-semibold text-on-surface p-0"
          />
          <span className="ml-1 text-label-md text-on-surface-variant">{units === 'yd' ? 'я' : 'м'}</span>
        </div>
      ) : (
        <div className="text-label-md text-on-surface-variant w-10 text-center shrink-0">—</div>
      )}
      <label className="min-h-touch min-w-touch shrink-0 flex items-center justify-center cursor-pointer">
        <input
          type="checkbox"
          checked={club.enabled}
          onChange={onToggle}
          aria-label={`Включить ${displayLabel} в сумку`}
          className="w-5 h-5 accent-primary cursor-pointer"
        />
      </label>
      {onDelete && (
        <button
          type="button"
          onClick={onDelete}
          aria-label="Удалить клюшку"
          className="min-h-touch min-w-touch shrink-0 flex items-center justify-center text-error text-title-lg leading-none rounded-full hover:bg-error-container/30 transition-colors"
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
          aria-label="Название новой клюшки"
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
            aria-label="Дистанция новой клюшки"
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
