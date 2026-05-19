import type { CourseResult } from '../types'
import { haversineMetres } from './distance'

const API_KEY = import.meta.env.VITE_GOOGLE_PLACES_API_KEY as string

interface PlacesResponse {
  status: string
  error_message?: string
  results: Array<{
    place_id: string
    name: string
    vicinity?: string
    rating?: number
    user_ratings_total?: number
    photos?: Array<{ photo_reference: string }>
    geometry: { location: { lat: number; lng: number } }
  }>
}

// Typed error so the UI can pick a specific message per failure mode.
export type CourseFetchErrorKind = 'config' | 'network' | 'denied' | 'quota' | 'invalid' | 'unknown'

export class CourseFetchError extends Error {
  constructor(public kind: CourseFetchErrorKind, message: string, public detail?: string) {
    super(message)
    this.name = 'CourseFetchError'
  }
}

export async function findNearbyCourses(
  lat: number,
  lng: number,
): Promise<CourseResult[]> {
  if (!API_KEY) {
    throw new CourseFetchError('config', 'API ключ Google Places не настроен')
  }

  const url = new URL('https://maps.googleapis.com/maps/api/place/nearbysearch/json')
  url.searchParams.set('location', `${lat},${lng}`)
  url.searchParams.set('radius', '20000')
  url.searchParams.set('type', 'golf_course')
  url.searchParams.set('key', API_KEY)

  // Note: Google Places API requires a server-side proxy in production
  // to avoid exposing the API key. For MVP/dev, we call directly.
  let res: Response
  try {
    res = await fetch(url.toString())
  } catch (e) {
    throw new CourseFetchError('network', 'Нет связи с серверами Google', String(e))
  }
  if (!res.ok) {
    throw new CourseFetchError('network', `Places API HTTP ${res.status}`)
  }

  const data = (await res.json()) as PlacesResponse

  if (data.status === 'ZERO_RESULTS') return []
  if (data.status !== 'OK') {
    const detail = data.error_message ?? ''
    if (data.status === 'REQUEST_DENIED') {
      throw new CourseFetchError(
        'denied',
        'Доступ к Google Places запрещён',
        detail || 'Скорее всего, текущий домен не в списке разрешённых в Google Cloud Console (HTTP referrers). Добавьте https://smart-golf-caddy.web.app/* в ограничения API-ключа.',
      )
    }
    if (data.status === 'OVER_QUERY_LIMIT') {
      throw new CourseFetchError('quota', 'Превышен лимит запросов к Google Places', detail)
    }
    if (data.status === 'INVALID_REQUEST') {
      throw new CourseFetchError('invalid', 'Некорректный запрос к Places API', detail)
    }
    throw new CourseFetchError('unknown', `Places API: ${data.status}`, detail)
  }

  return data.results.map((p) => ({
    placeId: p.place_id,
    name: p.name,
    vicinity: p.vicinity ?? '',
    rating: p.rating,
    userRatingsTotal: p.user_ratings_total,
    photoReference: p.photos?.[0]?.photo_reference,
    location: p.geometry.location,
    distanceKm: Math.round(haversineMetres(lat, lng, p.geometry.location.lat, p.geometry.location.lng) / 100) / 10,
  }))
}

// Google Place Photos URL — usable directly as <img src>.
// CORS allows browsers to fetch these. Costs 1 quota unit per request.
export function getCoursePhotoUrl(photoReference: string, maxWidth = 600): string {
  if (!API_KEY) return ''
  const url = new URL('https://maps.googleapis.com/maps/api/place/photo')
  url.searchParams.set('maxwidth', String(maxWidth))
  url.searchParams.set('photo_reference', photoReference)
  url.searchParams.set('key', API_KEY)
  return url.toString()
}
