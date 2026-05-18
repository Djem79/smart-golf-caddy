import { useEffect, useMemo, useState } from 'react'
import { useAuth } from '../hooks/useAuth'
import { useProfile } from '../hooks/useProfile'
import { updateBag, updateUnits } from '../services/users'
import { CLUB_ABBREV, CLUB_GROUPS, DEFAULT_BAG, getBagFromUser, metersToYards, yardsToMeters } from '../types'
import type { BagClub, DistanceUnit } from '../types'
import { Card } from '../components/ui/Card'
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

  // Sync from server profile on mount + when it changes
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
    const next = bag.map(c => c.id === id ? { ...c, enabled: !c.enabled } : c)
    await persistBag(next)
  }

  async function setName(id: string, name: string) {
    const trimmed = name.trim()
    const club = bag.find(c => c.id === id)
    if (!club) return
    if ((club.customName ?? '') === trimmed) return
    const next = bag.map(c => c.id === id ? { ...c, customName: trimmed || undefined } : c)
    await persistBag(next)
  }

  async function setDistance(id: string, raw: string) {
    const num = parseInt(raw, 10)
    if (Number.isNaN(num) || num < 0) return
    const meters = units === 'yd' ? yardsToMeters(num) : num
    const club = bag.find(c => c.id === id)
    if (!club || club.distanceMeters === meters) return
    const next = bag.map(c => c.id === id ? { ...c, distanceMeters: meters } : c)
    await persistBag(next)
  }

  async function changeUnits(u: DistanceUnit) {
    if (u === units) return
    setUnits(u)
    if (!user) return
    try { await updateUnits(user.uid, u) } catch { /* non-critical */ }
  }

  function distanceValue(club: BagClub): number {
    if (club.id === 'Putter') return 0
    return units === 'yd' ? metersToYards(club.distanceMeters) : club.distanceMeters
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
        {/* Counter + progress */}
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
        {CLUB_GROUPS.map(group => (
          <div key={group.label} className="space-y-2.5">
            <h3 className="font-headline font-semibold text-title-lg text-on-surface px-1">
              {group.label}
            </h3>
            <div className="space-y-2">
              {group.ids.map(id => {
                const club = bag.find(c => c.id === id)
                if (!club) return null
                return (
                  <div
                    key={id}
                    className={`flex items-center gap-3 p-3 bg-surface-container-lowest border border-outline-variant/30 rounded-lg transition-opacity ${!club.enabled ? 'opacity-60' : ''}`}
                  >
                    <div className="w-11 h-11 shrink-0 rounded-md bg-secondary-container flex items-center justify-center font-headline font-bold text-label-lg text-on-surface">
                      {CLUB_ABBREV[id] ?? id}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-semibold text-label-lg text-on-surface">{id}</p>
                      <input
                        type="text"
                        placeholder="Модель"
                        defaultValue={club.customName ?? ''}
                        onBlur={e => setName(id, e.target.value)}
                        className="w-full h-7 px-0 text-label-md bg-transparent border-none outline-none text-on-surface-variant placeholder:text-on-surface-variant/50"
                      />
                    </div>
                    {id !== 'Putter' ? (
                      <div className="flex items-center bg-surface-container rounded h-10 px-2 border border-outline-variant focus-within:border-primary">
                        <input
                          key={`${id}-${units}-${club.distanceMeters}`}
                          type="number"
                          inputMode="numeric"
                          min={0}
                          max={400}
                          defaultValue={distanceValue(club)}
                          onBlur={e => setDistance(id, e.target.value)}
                          className="w-12 bg-transparent border-none text-right text-label-md font-semibold text-on-surface outline-none p-0"
                        />
                        <span className="ml-1 text-label-md text-on-surface-variant">{units === 'yd' ? 'я' : 'м'}</span>
                      </div>
                    ) : (
                      <div className="text-label-md text-on-surface-variant w-16 text-center">—</div>
                    )}
                    <input
                      type="checkbox"
                      checked={club.enabled}
                      onChange={() => toggle(id)}
                      aria-label={`Включить ${id} в сумку`}
                      className="w-6 h-6 accent-primary cursor-pointer shrink-0"
                    />
                  </div>
                )
              })}
            </div>
          </div>
        ))}
      </div>

      <BottomNav />
    </div>
  )
}
