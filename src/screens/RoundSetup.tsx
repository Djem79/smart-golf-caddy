import { useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '../hooks/useAuth'
import { createRound } from '../services/rounds'
import type { CourseResult } from '../types'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'

export function RoundSetup() {
  const navigate = useNavigate()
  const location = useLocation()
  const { user } = useAuth()
  const course = (location.state as { course?: CourseResult } | null)?.course

  const [totalHoles, setTotalHoles] = useState<9 | 18>(18)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleStart() {
    if (!user || !course) return
    setError(null)
    setLoading(true)
    try {
      const roundId = await createRound(
        user.uid,
        {
          name: user.displayName ?? 'Голфер',
          avatar: user.photoURL ?? '',
          totalScore: 0,
          scoreDiff: 0,
        },
        course.placeId,
        course.name,
        totalHoles,
      )
      navigate(`/round/${roundId}/hole/1`)
    } catch (e) {
      console.error('Failed to create round', e)
      setError('Не удалось создать раунд. Попробуйте ещё раз.')
    } finally {
      setLoading(false)
    }
  }

  if (!course) {
    return (
      <div className="screen items-center justify-center px-5">
        <p className="text-body-md text-error">Поле не выбрано.</p>
        <Button onClick={() => navigate('/courses')} className="mt-4">
          Выбрать поле
        </Button>
      </div>
    )
  }

  return (
    <div className="screen">
      <PageHeader title="Настройка раунда" />

      <div className="px-5 pt-6 space-y-6 flex-1">
        <div className="card">
          <h2 className="font-headline font-bold text-title-lg text-on-surface">{course.name}</h2>
          <p className="text-label-lg text-on-surface-variant mt-1">{course.vicinity} · {course.distanceKm} км</p>
        </div>

        <div>
          <p className="font-semibold text-label-lg text-on-surface-variant mb-3 uppercase tracking-wider">
            Количество лунок
          </p>
          <div className="flex gap-3">
            {([9, 18] as const).map(n => (
              <button
                key={n}
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
      </div>

      <div className="px-5 pb-8 space-y-3">
        <Button onClick={handleStart} disabled={loading}>
          {loading ? 'Создаём раунд...' : 'Начать игру'}
        </Button>
        {error && (
          <p className="text-center text-label-lg text-error">{error}</p>
        )}
      </div>
    </div>
  )
}
