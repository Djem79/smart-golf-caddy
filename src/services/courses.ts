import type { CourseResult } from '../types'
import { haversineMetres } from './distance'

const API_KEY = import.meta.env.VITE_GOOGLE_PLACES_API_KEY as string

// Places API (New) — REST endpoint that supports CORS, designed for browser
// use. The legacy /maps/api/place/* endpoints under maps.googleapis.com do
// NOT send CORS headers and fail with "TypeError: Load failed" in Safari
// when called from any HTTPS origin other than the special-cased localhost.
const SEARCH_URL = 'https://places.googleapis.com/v1/places:searchNearby'

interface PlacesNewResponse {
  places?: Array<{
    id?: string
    displayName?: { text?: string }
    formattedAddress?: string
    rating?: number
    userRatingCount?: number
    photos?: Array<{ name: string }>
    location?: { latitude: number; longitude: number }
  }>
  error?: { code?: number; message?: string; status?: string }
}

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

  // FieldMask tells the API which fields to return — required by the new API
  // and helps minimise billing (you only pay for fields you request).
  const fieldMask = [
    'places.id',
    'places.displayName',
    'places.formattedAddress',
    'places.rating',
    'places.userRatingCount',
    'places.photos',
    'places.location',
  ].join(',')

  let res: Response
  try {
    res = await fetch(SEARCH_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': API_KEY,
        'X-Goog-FieldMask': fieldMask,
      },
      body: JSON.stringify({
        includedTypes: ['golf_course'],
        maxResultCount: 20,
        locationRestriction: {
          circle: {
            center: { latitude: lat, longitude: lng },
            radius: 20000.0,
          },
        },
      }),
    })
  } catch (e) {
    throw new CourseFetchError('network', 'Нет связи с серверами Google', String(e))
  }

  if (!res.ok) {
    // The new API returns structured error JSON for 4xx/5xx
    let detail = ''
    try {
      const body = (await res.json()) as PlacesNewResponse
      detail = body.error?.message ?? ''
    } catch { /* response wasn't JSON */ }

    if (res.status === 403) {
      throw new CourseFetchError(
        'denied',
        'Доступ к Places API (New) запрещён',
        detail || 'Проверьте, что Places API (New) включён в Google Cloud Console и что текущий домен добавлен в HTTP referrers для API-ключа: https://smart-golf-caddy.web.app/*',
      )
    }
    if (res.status === 429) {
      throw new CourseFetchError('quota', 'Превышен лимит запросов к Places API', detail)
    }
    if (res.status === 400) {
      throw new CourseFetchError('invalid', 'Некорректный запрос к Places API', detail)
    }
    throw new CourseFetchError('unknown', `Places API HTTP ${res.status}`, detail)
  }

  const data = (await res.json()) as PlacesNewResponse
  const places = data.places ?? []

  return places.map(p => {
    const placeLat = p.location?.latitude ?? lat
    const placeLng = p.location?.longitude ?? lng
    return {
      placeId: p.id ?? '',
      name: p.displayName?.text ?? 'Поле для гольфа',
      vicinity: p.formattedAddress ?? '',
      rating: p.rating,
      userRatingsTotal: p.userRatingCount,
      photoUrl: p.photos?.[0]?.name ? buildPhotoUrl(p.photos[0].name, 800) : undefined,
      location: { lat: placeLat, lng: placeLng },
      distanceKm: Math.round(haversineMetres(lat, lng, placeLat, placeLng) / 100) / 10,
    }
  })
}

// Places API (New) photo endpoint. The browser <img> tag follows the 302
// redirect from this URL to the actual image automatically, and CORS is
// configured permissively for photo media.
function buildPhotoUrl(photoName: string, maxWidth: number): string {
  if (!API_KEY) return ''
  return `https://places.googleapis.com/v1/${photoName}/media?maxWidthPx=${maxWidth}&key=${API_KEY}`
}

// Backward-compat shim kept so existing imports don't break — accepts a
// resource name OR a pre-built URL and returns a usable <img src>.
export function getCoursePhotoUrl(photoRef: string, maxWidth = 600): string {
  if (!photoRef) return ''
  // The new API gives us a fully-formed URL via photoUrl on CourseResult;
  // this helper just exists for legacy callers that still pass a raw ref.
  if (photoRef.startsWith('http')) return photoRef
  return buildPhotoUrl(photoRef, maxWidth)
}
