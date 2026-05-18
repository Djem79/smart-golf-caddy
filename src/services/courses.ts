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
    geometry: { location: { lat: number; lng: number } }
  }>
}

export async function findNearbyCourses(
  lat: number,
  lng: number,
): Promise<CourseResult[]> {
  if (!API_KEY) {
    throw new Error('VITE_GOOGLE_PLACES_API_KEY is not configured')
  }

  const url = new URL('https://maps.googleapis.com/maps/api/place/nearbysearch/json')
  url.searchParams.set('location', `${lat},${lng}`)
  url.searchParams.set('radius', '20000')
  url.searchParams.set('type', 'golf_course')
  url.searchParams.set('key', API_KEY)

  // Note: Google Places API requires a server-side proxy in production
  // to avoid exposing the API key. For MVP/dev, we call directly.
  const res = await fetch(url.toString())
  if (!res.ok) throw new Error(`Places API HTTP error: ${res.status}`)

  const data = (await res.json()) as PlacesResponse

  if (data.status === 'ZERO_RESULTS') return []
  if (data.status !== 'OK') {
    throw new Error(`Places API error: ${data.status}${data.error_message ? ` — ${data.error_message}` : ''}`)
  }

  return data.results.map((p) => ({
    placeId: p.place_id,
    name: p.name,
    vicinity: p.vicinity ?? '',
    location: p.geometry.location,
    distanceKm: Math.round(haversineMetres(lat, lng, p.geometry.location.lat, p.geometry.location.lng) / 100) / 10,
  }))
}
