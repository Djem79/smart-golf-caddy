import type { CourseResult } from '../types'
import { haversineMetres } from './distance'

const API_KEY = import.meta.env.VITE_GOOGLE_PLACES_API_KEY as string

// Places API (New) — REST endpoint that supports CORS, designed for browser
// use. The legacy /maps/api/place/* endpoints under maps.googleapis.com do
// NOT send CORS headers and fail with "TypeError: Load failed" in Safari
// when called from any HTTPS origin other than the special-cased localhost.
const SEARCH_URL = 'https://places.googleapis.com/v1/places:searchNearby'
const TEXT_SEARCH_URL = 'https://places.googleapis.com/v1/places:searchText'

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
// Which endpoint the error came from — 'denied'/'quota' read differently
// depending on it (see t.courseSearch.fetchErrors.*New vs non-New), since
// findNearbyCourses and searchCoursesByText hit different Places API
// surfaces with different setup requirements.
export type CourseFetchErrorSource = 'nearby' | 'text'

// Carries only a machine-readable kind/source + optional raw detail from the
// Google API response — no translated text. This is a plain service module
// (services/ → firebase.ts (only) + Cloud Functions callables per
// CLAUDE.md), so it must not depend on the i18n/view layer; the call site
// (CourseSearch screen) maps kind+source to copy via useT(), the same
// pattern getClubLabel(clubId, bag, fallbacks) uses in types/index.ts.
export class CourseFetchError extends Error {
  constructor(
    public kind: CourseFetchErrorKind,
    public source: CourseFetchErrorSource,
    public detail?: string,
  ) {
    // Error.message here is a technical identifier for logs/Sentry only —
    // never rendered directly; the UI derives display text from kind+source.
    super(`CourseFetchError:${source}:${kind}`)
    this.name = 'CourseFetchError'
  }
}

export async function findNearbyCourses(
  lat: number,
  lng: number,
): Promise<CourseResult[]> {
  if (!API_KEY) {
    throw new CourseFetchError('config', 'nearby')
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
    throw new CourseFetchError('network', 'nearby', String(e))
  }

  if (!res.ok) {
    // The new API returns structured error JSON for 4xx/5xx
    let detail = ''
    try {
      const body = (await res.json()) as PlacesNewResponse
      detail = body.error?.message ?? ''
    } catch { /* response wasn't JSON */ }

    if (res.status === 403) {
      throw new CourseFetchError('denied', 'nearby', detail || undefined)
    }
    if (res.status === 429) {
      throw new CourseFetchError('quota', 'nearby', detail || undefined)
    }
    if (res.status === 400) {
      throw new CourseFetchError('invalid', 'nearby', detail || undefined)
    }
    throw new CourseFetchError('unknown', 'nearby', detail || `HTTP ${res.status}`)
  }

  const data = (await res.json()) as PlacesNewResponse
  const places = data.places ?? []

  return places.map(p => {
    const placeLat = p.location?.latitude ?? lat
    const placeLng = p.location?.longitude ?? lng
    return {
      placeId: p.id ?? '',
      // Empty when Google doesn't return a display name (rare) — the
      // caller (CourseSearch screen) substitutes a translated placeholder
      // via t.common.golfCourseFallback rather than this service picking one.
      name: p.displayName?.text ?? '',
      vicinity: p.formattedAddress ?? '',
      rating: p.rating,
      userRatingsTotal: p.userRatingCount,
      photoUrl: p.photos?.[0]?.name ? buildPhotoUrl(p.photos[0].name, 800) : undefined,
      location: { lat: placeLat, lng: placeLng },
      distanceKm: Math.round(haversineMetres(lat, lng, placeLat, placeLng) / 100) / 10,
    }
  })
}

// Free-form text search via Places API (New). Used for queries that may
// match places outside the geolocation radius (e.g. "Завидово Гольф"
// from anywhere). If `bias` (current lat/lng) is supplied, results near
// the user rank higher; without it, the search is global.
export async function searchCoursesByText(
  query: string,
  bias?: { lat: number; lng: number },
): Promise<CourseResult[]> {
  const q = query.trim()
  if (q.length === 0) return []
  if (!API_KEY) {
    throw new CourseFetchError('config', 'text')
  }

  const fieldMask = [
    'places.id',
    'places.displayName',
    'places.formattedAddress',
    'places.rating',
    'places.userRatingCount',
    'places.photos',
    'places.location',
  ].join(',')

  // We constrain to golf courses; Google rejects mixing free-form text
  // queries with `includedTypes` arrays on this endpoint, so we use the
  // single-type `includedType` field instead.
  const body: Record<string, unknown> = {
    textQuery: q,
    includedType: 'golf_course',
    maxResultCount: 20,
  }
  if (bias) {
    body.locationBias = {
      circle: {
        center: { latitude: bias.lat, longitude: bias.lng },
        radius: 50000.0,
      },
    }
  }

  let res: Response
  try {
    res = await fetch(TEXT_SEARCH_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': API_KEY,
        'X-Goog-FieldMask': fieldMask,
      },
      body: JSON.stringify(body),
    })
  } catch (e) {
    throw new CourseFetchError('network', 'text', String(e))
  }

  if (!res.ok) {
    let detail = ''
    try {
      const errBody = (await res.json()) as PlacesNewResponse
      detail = errBody.error?.message ?? ''
    } catch { /* not json */ }
    if (res.status === 403) {
      throw new CourseFetchError('denied', 'text', detail || undefined)
    }
    if (res.status === 429) {
      throw new CourseFetchError('quota', 'text', detail || undefined)
    }
    throw new CourseFetchError('unknown', 'text', detail || `HTTP ${res.status}`)
  }

  const data = (await res.json()) as PlacesNewResponse
  const places = data.places ?? []

  return places.map(p => {
    const placeLat = p.location?.latitude ?? 0
    const placeLng = p.location?.longitude ?? 0
    const distanceKm = bias
      ? Math.round(haversineMetres(bias.lat, bias.lng, placeLat, placeLng) / 100) / 10
      : 0
    return {
      placeId: p.id ?? '',
      name: p.displayName?.text ?? '',
      vicinity: p.formattedAddress ?? '',
      rating: p.rating,
      userRatingsTotal: p.userRatingCount,
      photoUrl: p.photos?.[0]?.name ? buildPhotoUrl(p.photos[0].name, 800) : undefined,
      location: { lat: placeLat, lng: placeLng },
      distanceKm,
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
