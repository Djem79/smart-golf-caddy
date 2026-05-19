import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useGeolocation } from '../hooks/useGeolocation'
import { findNearbyCourses, searchCoursesByText, CourseFetchError } from '../services/courses'
import type { CourseResult } from '../types'
import { Button } from '../components/ui/Button'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'
import { pluralRu } from '../utils/intl'

export function CourseSearch() {
  const navigate = useNavigate()
  const { lat, lng, error: geoError, loading: geoLoading, request: requestLocation } = useGeolocation()
  const [nearby, setNearby] = useState<CourseResult[]>([])
  const [nearbyLoading, setNearbyLoading] = useState(false)
  const [textResults, setTextResults] = useState<CourseResult[] | null>(null)
  const [textLoading, setTextLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [search, setSearch] = useState('')

  // 1) Nearby search — runs once geolocation resolves
  useEffect(() => {
    if (lat == null || lng == null) return
    let cancelled = false
    setNearbyLoading(true)
    setError(null)
    findNearbyCourses(lat, lng)
      .then(r => { if (!cancelled) setNearby(r) })
      .catch((e: unknown) => {
        if (cancelled) return
        if (e instanceof CourseFetchError) {
          const detail = e.detail ? ` ${e.detail}` : ''
          setError(`${e.message}.${detail}`)
        } else {
          setError('Не удалось загрузить поля. Проверьте интернет.')
        }
        if (import.meta.env.DEV) console.error('[CourseSearch] findNearbyCourses failed:', e)
      })
      .finally(() => { if (!cancelled) setNearbyLoading(false) })
    return () => { cancelled = true }
  }, [lat, lng])

  // 2) Debounced text search — runs whenever the input changes (>= 2 chars)
  useEffect(() => {
    const q = search.trim()
    if (q.length < 2) {
      setTextResults(null)
      return
    }
    let cancelled = false
    setTextLoading(true)
    const timer = window.setTimeout(() => {
      const bias = (lat != null && lng != null) ? { lat, lng } : undefined
      searchCoursesByText(q, bias)
        .then(r => { if (!cancelled) setTextResults(r) })
        .catch((e: unknown) => {
          if (cancelled) return
          // Don't replace the global nearby error; fall back to local filter.
          setTextResults([])
          if (import.meta.env.DEV) console.error('[CourseSearch] searchCoursesByText failed:', e)
        })
        .finally(() => { if (!cancelled) setTextLoading(false) })
    }, 400)
    return () => { cancelled = true; window.clearTimeout(timer) }
  }, [search, lat, lng])

  // What gets rendered. When the user is searching by text, show those
  // results. Otherwise show nearby. Always also apply a local substring
  // match so 1-character queries still filter the nearby list instantly.
  const visible = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (textResults != null) return textResults
    if (q.length === 0) return nearby
    return nearby.filter(c =>
      c.name.toLowerCase().includes(q) || c.vicinity.toLowerCase().includes(q),
    )
  }, [nearby, textResults, search])

  const loading = nearbyLoading || textLoading
  const isTextSearch = textResults != null

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
            className="w-full h-14 pl-11 pr-4 bg-surface-container-low border-none rounded-md text-body-md shadow-card placeholder:text-on-surface-variant/60"
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
          <h2 className="font-headline font-bold text-headline-md text-on-surface">
            {isTextSearch ? 'Результаты поиска' : 'Ближайшие поля'}
          </h2>
          {visible.length > 0 && (
            <span className="text-label-lg text-on-surface-variant">
              {visible.length} {pluralRu(visible.length, 'поле', 'поля', 'полей')}
            </span>
          )}
        </div>

        {!isTextSearch && geoLoading && (
          <div className="text-center pt-8 space-y-3">
            <p className="text-on-surface-variant text-body-md">Определяем вашу позицию...</p>
            <button
              type="button"
              onClick={requestLocation}
              className="text-label-lg text-primary font-semibold underline min-h-touch px-3"
            >
              Запросить разрешение вручную
            </button>
          </div>
        )}
        {!isTextSearch && geoError && (
          <div className="text-center pt-8 space-y-3">
            <p className="text-error text-body-md px-4">{geoError}</p>
            <Button onClick={requestLocation}>📍 Определить местоположение</Button>
            <p className="text-label-md text-on-surface-variant">
              Или введите название поля в поиске выше — он работает и без геолокации
            </p>
          </div>
        )}
        {loading && visible.length === 0 && (
          <div className="space-y-4">
            {[0, 1].map(i => <SkeletonCard key={i} />)}
          </div>
        )}
        {error && !isTextSearch && (
          <p className="text-center text-error text-body-md pt-8">{error}</p>
        )}

        <div className="space-y-4">
          {visible.map(course => (
            <CourseCard key={course.placeId} course={course} onSelect={selectCourse} />
          ))}
        </div>

        {!loading && !geoLoading && visible.length === 0 && (nearby.length > 0 || isTextSearch) && (
          <p className="text-center text-on-surface-variant text-body-md pt-4">
            {isTextSearch ? `По запросу «${search.trim()}» поля не найдены` : 'Поля не найдены'}
          </p>
        )}
      </div>

      <BottomNav />
    </div>
  )
}

function CourseCard({ course, onSelect }: { course: CourseResult; onSelect: (c: CourseResult) => void }) {
  const photoUrl = course.photoUrl ?? null

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
