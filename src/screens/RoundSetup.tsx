import { useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { User, Users, BarChart3, Swords, type LucideIcon } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { createRound } from '../services/rounds'
import type { CourseResult, TeeColor, PlayMode } from '../types'
import { TEE_LABELS } from '../types'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'

interface RoundSetupState {
  course?: CourseResult
  customName?: string
}

export function RoundSetup() {
  const navigate = useNavigate()
  const location = useLocation()
  const { user } = useAuth()
  const state = (location.state as RoundSetupState | null) ?? {}
  const course = state.course

  const [customName, setCustomName] = useState(state.customName ?? '')
  const [totalHoles, setTotalHoles] = useState<9 | 18>(18)
  const [mode, setMode] = useState<'solo' | 'group'>('solo')
  const [tee, setTee] = useState<TeeColor>('men')
  const [playMode, setPlayMode] = useState<PlayMode>('stroke')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const effectiveName = course?.name ?? (customName.trim() || 'Поле для гольфа')

  async function handleStart() {
    if (!user) return
    setError(null)
    setLoading(true)
    // Only generate the synthetic course id at submit time — calling Date.now()
    // in the render body would create a new id on every keystroke.
    const effectiveId = course?.placeId ?? `custom-${Date.now()}`
    try {
      const roundId = await createRound(
        user.uid,
        {
          name: user.displayName ?? 'Голфер',
          avatar: user.photoURL ?? '',
          totalScore: 0,
          scoreDiff: 0,
          email: user.email ?? '',
        },
        effectiveId,
        effectiveName,
        totalHoles,
        mode,
        tee,
        playMode,
      )
      if (mode === 'group') {
        navigate(`/round/${roundId}/lobby`)
      } else {
        navigate(`/round/${roundId}/hole/1`)
      }
    } catch (e) {
      console.error('Failed to create round', e)
      setError('Не удалось создать раунд. Попробуйте ещё раз.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="screen pb-20">
      <PageHeader title="Настройка раунда" />

      <div className="px-5 pt-6 space-y-6 flex-1">
        {course ? (
          <div className="card">
            <h2 className="font-headline font-bold text-title-lg text-on-surface">{course.name}</h2>
            <p className="text-label-lg text-on-surface-variant mt-1">{course.vicinity} · {course.distanceKm} км</p>
            <button
              type="button"
              onClick={() => navigate('/courses')}
              className="text-label-lg text-primary font-semibold mt-3"
            >
              Сменить поле
            </button>
          </div>
        ) : (
          <div className="space-y-2">
            <p className="font-semibold text-label-lg text-on-surface-variant uppercase tracking-wider">
              Название поля
            </p>
            <input
              type="text"
              placeholder="Например: Гольф клуб Москва"
              value={customName}
              onChange={e => setCustomName(e.target.value)}
              className="w-full border border-outline-variant rounded px-4 py-3 text-body-md bg-surface-container-lowest focus:border-primary"
            />
            <button
              type="button"
              onClick={() => navigate('/courses')}
              className="text-label-lg text-primary font-semibold"
            >
              Найти ближайшее поле
            </button>
          </div>
        )}

        <div>
          <p className="font-semibold text-label-lg text-on-surface-variant mb-3 uppercase tracking-wider">
            Количество лунок
          </p>
          <div className="flex gap-3">
            {([9, 18] as const).map(n => (
              <button
                key={n}
                type="button"
                onClick={() => setTotalHoles(n)}
                className={`flex-1 min-h-touch rounded font-headline font-bold text-title-lg border-2 transition-colors ${
                  totalHoles === n
                    ? 'border-primary bg-primary text-on-primary'
                    : 'border-outline-variant text-on-surface-variant'
                }`}
              >
                {n}
              </button>
            ))}
          </div>
        </div>

        <div>
          <p className="font-semibold text-label-lg text-on-surface-variant mb-3 uppercase tracking-wider">
            Тии (откуда играем)
          </p>
          <div className="grid grid-cols-2 gap-2">
            {(['pro', 'men', 'senior', 'ladies'] as const).map(t => {
              const info = TEE_LABELS[t]
              const selected = tee === t
              return (
                <button
                  key={t}
                  type="button"
                  onClick={() => setTee(t)}
                  aria-pressed={selected}
                  className={`flex flex-col items-start gap-2 p-3 rounded-lg border-2 transition-colors text-left min-h-[96px] ${
                    selected
                      ? 'border-primary bg-primary-container/10'
                      : 'border-outline-variant/60 bg-surface-container-lowest'
                  }`}
                >
                  <div
                    className="w-7 h-7 shrink-0 rounded-full border border-outline-variant/40 flex items-center justify-center font-bold text-label-md"
                    style={{ backgroundColor: info.bg, color: info.text }}
                  >
                    T
                  </div>
                  <div className="min-w-0">
                    <p className="font-semibold text-label-lg text-on-surface leading-tight">
                      {info.label}
                    </p>
                    <p className="text-label-md text-on-surface-variant leading-tight mt-0.5">
                      {info.description}
                    </p>
                  </div>
                </button>
              )
            })}
          </div>
        </div>

        <div>
          <p className="font-semibold text-label-lg text-on-surface-variant mb-3 uppercase tracking-wider">
            Режим игры
          </p>
          <div className="grid grid-cols-2 gap-3">
            {([
              { id: 'solo' as const,  Icon: User,  title: 'Соло',   desc: 'Только вы' },
              { id: 'group' as const, Icon: Users, title: 'Группа', desc: 'С друзьями' },
            ] satisfies { id: 'solo' | 'group'; Icon: LucideIcon; title: string; desc: string }[]).map(opt => (
              <ChoiceCard
                key={opt.id}
                selected={mode === opt.id}
                Icon={opt.Icon}
                title={opt.title}
                desc={opt.desc}
                onClick={() => setMode(opt.id)}
              />
            ))}
          </div>
          {mode === 'group' && (
            <p className="text-label-md text-on-surface-variant mt-2 text-center">
              После создания раунда вы получите код, чтобы пригласить друзей
            </p>
          )}
        </div>

        {/* Play mode — only meaningful for group rounds */}
        {mode === 'group' && (
          <div>
            <p className="font-semibold text-label-lg text-on-surface-variant mb-3 uppercase tracking-wider">
              Формат игры
            </p>
            <div className="grid grid-cols-2 gap-3">
              {([
                { id: 'stroke' as const, Icon: BarChart3, title: 'Stroke', desc: 'Общий счёт по ударам' },
                { id: 'match'  as const, Icon: Swords,    title: 'Match',  desc: '2 игрока · по лункам' },
              ] satisfies { id: 'stroke' | 'match'; Icon: LucideIcon; title: string; desc: string }[]).map(opt => (
                <ChoiceCard
                  key={opt.id}
                  selected={playMode === opt.id}
                  Icon={opt.Icon}
                  title={opt.title}
                  desc={opt.desc}
                  onClick={() => setPlayMode(opt.id)}
                />
              ))}
            </div>
            {playMode === 'match' && (
              <p className="text-label-md text-on-surface-variant mt-2 text-center">
                Match play считается по победам в каждой лунке. Лучше всего работает 1v1.
              </p>
            )}
          </div>
        )}
      </div>

      <div
        className="px-5 pt-8 space-y-3 border-t border-outline-variant/30 mt-8"
        style={{ paddingBottom: 'max(2rem, env(safe-area-inset-bottom))' }}
      >
        <Button onClick={handleStart} disabled={loading}>
          {loading
            ? 'Создаём раунд...'
            : mode === 'group'
              ? 'Создать лобби'
              : 'Начать игру'}
        </Button>
        {error && (
          <p className="text-center text-label-lg text-error">{error}</p>
        )}
      </div>

      <BottomNav />
    </div>
  )
}

interface ChoiceCardProps {
  Icon: LucideIcon
  title: string
  desc: string
  selected: boolean
  onClick: () => void
}

function ChoiceCard({ Icon, title, desc, selected, onClick }: ChoiceCardProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={selected}
      className={`flex flex-col items-start gap-2 p-4 rounded-lg border-2 transition-all duration-150 text-left min-h-[120px] ${
        selected
          ? 'border-primary bg-primary-container/10 text-on-surface'
          : 'border-outline-variant/60 bg-surface-container-lowest text-on-surface-variant hover:border-outline-variant'
      }`}
    >
      <span
        className={`w-9 h-9 rounded-md flex items-center justify-center transition-colors ${
          selected ? 'bg-primary text-on-primary' : 'bg-surface-container text-on-surface-variant'
        }`}
      >
        <Icon size={20} strokeWidth={1.75} />
      </span>
      <div>
        <p className={`font-headline font-semibold text-label-lg ${selected ? 'text-on-surface' : 'text-on-surface'}`}>
          {title}
        </p>
        <p className="text-label-md text-on-surface-variant mt-0.5">{desc}</p>
      </div>
    </button>
  )
}
