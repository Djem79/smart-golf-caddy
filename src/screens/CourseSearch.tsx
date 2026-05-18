import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useGeolocation } from '../hooks/useGeolocation'
import { findNearbyCourses } from '../services/courses'
import type { CourseResult } from '../types'
import { Card } from '../components/ui/Card'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'

export function CourseSearch() {
  const navigate = useNavigate()
  const { lat, lng, error: geoError, loading: geoLoading } = useGeolocation()
  const [courses, setCourses] = useState<CourseResult[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState('')

  useEffect(() => {
    if (lat == null || lng == null) return
    let cancelled = false
    setLoading(true)
    setError(null)
    findNearbyCourses(lat, lng)
      .then(r => { if (!cancelled) setCourses(r) })
      .catch(() => { if (!cancelled) setError('Не удалось загрузить поля. Проверьте интернет.') })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [lat, lng])

  const filtered = courses.filter(c =>
    c.name.toLowerCase().includes(search.toLowerCase()),
  )

  function selectCourse(course: CourseResult) {
    navigate('/round/setup', { state: { course } })
  }

  function skipSelection() {
    navigate('/round/setup', { state: { customName: search.trim() || undefined } })
  }

  return (
    <div className="screen">
      <PageHeader title="Поиск полей" />

      <div className="px-5 pt-4 pb-2 space-y-3">
        <input
          type="text"
          placeholder="Поиск по названию..."
          value={search}
          onChange={e => setSearch(e.target.value)}
          className="w-full border border-outline-variant rounded px-4 py-3 text-body-md bg-surface-container-lowest outline-none focus:border-primary"
        />
        <Button variant="secondary" onClick={skipSelection}>
          {search.trim() ? `Использовать «${search.trim()}»` : 'Указать поле вручную / пропустить'}
        </Button>
      </div>

      <div className="flex-1 px-5 pb-6 space-y-3 overflow-y-auto">
        {geoLoading && (
          <p className="text-center text-on-surface-variant text-body-md pt-8">
            Определяем вашу позицию...
          </p>
        )}
        {geoError && (
          <p className="text-center text-error text-body-md pt-8">
            {geoError}. Введите название поля выше.
          </p>
        )}
        {loading && (
          <p className="text-center text-on-surface-variant text-body-md pt-8">
            Ищем ближайшие поля...
          </p>
        )}
        {error && (
          <p className="text-center text-error text-body-md pt-8">{error}</p>
        )}
        {filtered.map(course => (
          <Card key={course.placeId} onClick={() => selectCourse(course)}>
            <div className="flex items-center justify-between">
              <div>
                <h3 className="font-headline font-semibold text-title-lg text-on-surface">{course.name}</h3>
                <p className="text-label-lg text-on-surface-variant mt-1">{course.vicinity}</p>
              </div>
              <span className="font-headline font-bold text-headline-md text-primary shrink-0 ml-3">
                {course.distanceKm} км
              </span>
            </div>
          </Card>
        ))}
        {!loading && !geoLoading && filtered.length === 0 && courses.length > 0 && (
          <p className="text-center text-on-surface-variant text-body-md pt-4">Поля не найдены</p>
        )}
      </div>
    </div>
  )
}
