import { useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
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
                  className={`flex items-center gap-3 p-3 rounded-lg border-2 transition-colors text-left ${
                    selected ? 'border-primary bg-primary-container/15' : 'border-outline-variant'
                  }`}
                >
                  <div
                    className="w-8 h-8 shrink-0 rounded-full border border-outline-variant/40 flex items-center justify-center font-bold text-label-md"
                    style={{ backgroundColor: info.bg, color: info.text }}
                  >
                    T
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-label-lg text-on-surface truncate">{info.label}</p>
                    <p className="text-label-md text-on-surface-variant truncate">{info.description}</p>
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
              { id: 'solo' as const,  emoji: '⛳', title: 'Соло',   desc: 'Только вы' },
              { id: 'group' as const, emoji: '👥', title: 'Группа', desc: 'С друзьями' },
            ]).map(opt => (
              <button
                key={opt.id}
                type="button"
                onClick={() => setMode(opt.id)}
                className={`flex flex-col items-center justify-center gap-1 p-4 rounded-lg border-2 transition-colors ${
                  mode === opt.id
                    ? 'border-primary bg-primary-container/15 text-on-surface'
                    : 'border-outline-variant text-on-surface-variant'
                }`}
              >
                <span className="text-3xl">{opt.emoji}</span>
                <span className="font-headline font-semibold text-label-lg">{opt.title}</span>
                <span className="text-label-md text-on-surface-variant">{opt.desc}</span>
              </button>
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
                { id: 'stroke' as const, emoji: '📊', title: 'Stroke', desc: 'Общий счёт по ударам' },
                { id: 'match'  as const, emoji: '🤝', title: 'Match',  desc: '2 игрока · по лункам' },
              ]).map(opt => (
                <button
                  key={opt.id}
                  type="button"
                  onClick={() => setPlayMode(opt.id)}
                  className={`flex flex-col items-center justify-center gap-1 p-4 rounded-lg border-2 transition-colors ${
                    playMode === opt.id
                      ? 'border-primary bg-primary-container/15 text-on-surface'
                      : 'border-outline-variant text-on-surface-variant'
                  }`}
                >
                  <span className="text-3xl">{opt.emoji}</span>
                  <span className="font-headline font-semibold text-label-lg">{opt.title}</span>
                  <span className="text-label-md text-on-surface-variant">{opt.desc}</span>
                </button>
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

      <div className="px-5 pb-8 space-y-3">
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
