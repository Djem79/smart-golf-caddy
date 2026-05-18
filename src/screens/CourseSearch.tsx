import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useGeolocation } from '../hooks/useGeolocation'
import { findNearbyCourses, getCoursePhotoUrl } from '../services/courses'
import type { CourseResult } from '../types'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'

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
    c.name.toLowerCase().includes(search.toLowerCase())
    || c.vicinity.toLowerCase().includes(search.toLowerCase()),
  )

  function selectCourse(course: CourseResult) {
    navigate('/round/setup', { state: { course } })
  }

  function skipSelection() {
    navigate('/round/setup', { state: { customName: search.trim() || undefined } })
  }

  return (
    <div className="screen pb-20">
      <PageHeader title="Поиск полей" />

      {/* Search field */}
      <div className="px-5 pt-4 pb-2">
        <div className="relative">
          <span className="absolute left-4 top-1/2 -translate-y-1/2 text-on-surface-variant text-headline-md select-none">⌕</span>
          <input
            type="text"
            placeholder="Поиск полей или городов"
            value={search}
            onChange={e => setSearch(e.target.value)}
            className="w-full h-14 pl-11 pr-4 bg-surface-container-low border-none rounded-md text-body-md shadow-card outline-none focus:ring-2 focus:ring-primary placeholder:text-on-surface-variant/60"
          />
        </div>
      </div>

      {/* Skip / manual entry */}
      <div className="px-5 pb-2">
        <Button variant="secondary" onClick={skipSelection}>
          {search.trim() ? `Использовать «${search.trim()}»` : 'Указать поле вручную / пропустить'}
        </Button>
      </div>

      {/* List */}
      <div className="flex-1 px-5 pb-6 overflow-y-auto">
        <div className="flex items-baseline justify-between mb-3 pt-2">
          <h2 className="font-headline font-bold text-headline-md text-on-surface">Ближайшие поля</h2>
          {filtered.length > 0 && (
            <span className="text-label-lg text-on-surface-variant">
              {filtered.length} {pluralRu(filtered.length, 'поле', 'поля', 'полей')}
            </span>
          )}
        </div>

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
          <div className="space-y-4">
            {[0, 1].map(i => <SkeletonCard key={i} />)}
          </div>
        )}
        {error && (
          <p className="text-center text-error text-body-md pt-8">{error}</p>
        )}

        <div className="space-y-4">
          {filtered.map(course => (
            <CourseCard key={course.placeId} course={course} onSelect={selectCourse} />
          ))}
        </div>

        {!loading && !geoLoading && filtered.length === 0 && courses.length > 0 && (
          <p className="text-center text-on-surface-variant text-body-md pt-4">Поля не найдены</p>
        )}
      </div>

      <BottomNav />
    </div>
  )
}

function CourseCard({ course, onSelect }: { course: CourseResult; onSelect: (c: CourseResult) => void }) {
  const photoUrl = course.photoReference ? getCoursePhotoUrl(course.photoReference, 800) : null

  return (
    <div className="bg-surface-container-lowest rounded-lg border border-outline-variant/30 shadow-card overflow-hidden">
      {/* Hero image */}
      <div className="relative h-40 bg-gradient-to-br from-primary-container to-secondary-container">
        {photoUrl ? (
          <img src={photoUrl} alt={course.name} className="w-full h-full object-cover" loading="lazy" />
        ) : (
          <div className="w-full h-full flex items-center justify-center text-6xl opacity-30">⛳</div>
        )}
        {/* Distance badge */}
        <div className="absolute top-3 left-3 bg-primary text-on-primary px-3 py-1 rounded-full text-label-md font-bold shadow-card">
          {course.distanceKm} км
        </div>
        {/* Rating badge */}
        {course.rating != null && (
          <div className="absolute top-3 right-3 bg-surface-container-lowest text-on-surface px-2.5 py-1 rounded-full text-label-md font-semibold shadow-card flex items-center gap-1">
            <span className="text-[#FFC107]">★</span>
            {course.rating.toFixed(1)}
          </div>
        )}
      </div>

      {/* Content */}
      <div className="p-4 space-y-3">
        <div>
          <h3 className="font-headline font-bold text-title-lg text-on-surface leading-tight">{course.name}</h3>
          {course.vicinity && (
            <p className="text-label-lg text-on-surface-variant mt-1 flex items-start gap-1">
              <span className="shrink-0 mt-0.5">📍</span>
              <span>{course.vicinity}</span>
            </p>
          )}
        </div>

        {course.userRatingsTotal != null && course.userRatingsTotal > 0 && (
          <div className="flex flex-wrap gap-1.5">
            <span className="bg-surface-container px-2 py-0.5 rounded text-label-md font-semibold text-on-surface-variant">
              {course.userRatingsTotal} {pluralRu(course.userRatingsTotal, 'отзыв', 'отзыва', 'отзывов')}
            </span>
          </div>
        )}

        <Button onClick={() => onSelect(course)}>Выбрать это поле</Button>
      </div>
    </div>
  )
}

function SkeletonCard() {
  return (
    <div className="bg-surface-container-lowest rounded-lg border border-outline-variant/30 overflow-hidden animate-pulse">
      <div className="h-40 bg-surface-container" />
      <div className="p-4 space-y-3">
        <div className="h-5 w-2/3 bg-surface-container rounded" />
        <div className="h-4 w-1/2 bg-surface-container rounded" />
        <div className="h-12 bg-surface-container rounded" />
      </div>
    </div>
  )
}

// Russian noun pluralization: 1 → форма1, 2-4 → форма2, прочие → форма3
function pluralRu(n: number, one: string, few: string, many: string): string {
  const mod10 = n % 10
  const mod100 = n % 100
  if (mod10 === 1 && mod100 !== 11) return one
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few
  return many
}
