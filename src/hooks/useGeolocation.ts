import { useState, useEffect } from 'react'

export interface GeoState {
  lat: number | null
  lng: number | null
  error: string | null
  loading: boolean
}

export function useGeolocation(): GeoState {
  const [state, setState] = useState<GeoState>({
    lat: null, lng: null, error: null, loading: true,
  })

  useEffect(() => {
    if (!navigator.geolocation) {
      setState({ lat: null, lng: null, error: 'Геолокация не поддерживается', loading: false })
      return
    }
    const watchId = navigator.geolocation.watchPosition(
      ({ coords }) => setState({
        lat: coords.latitude,
        lng: coords.longitude,
        error: null,
        loading: false,
      }),
      (err) => setState({ lat: null, lng: null, error: err.message, loading: false }),
      { enableHighAccuracy: true, maximumAge: 5000 },
    )
    return () => navigator.geolocation.clearWatch(watchId)
  }, [])

  return state
}
