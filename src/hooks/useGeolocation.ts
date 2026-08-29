import { useState, useEffect, useCallback, useRef } from 'react'
import { useT } from '../i18n'

export interface GeoState {
  lat: number | null
  lng: number | null
  error: string | null
  loading: boolean
  /** Re-request location — call from a user gesture for browsers that require it. */
  request: () => void
}

const WATCH_OPTIONS: PositionOptions = {
  enableHighAccuracy: true,
  maximumAge: 5000,
  // iOS Safari otherwise hangs indefinitely with no permission prompt visible.
  timeout: 20_000,
}

export function useGeolocation(): GeoState {
  const { t } = useT()
  const [state, setState] = useState<Omit<GeoState, 'request'>>({
    lat: null, lng: null, error: null, loading: true,
  })
  const watchIdRef = useRef<number | null>(null)

  const start = useCallback(() => {
    if (typeof navigator === 'undefined' || !navigator.geolocation) {
      setState({ lat: null, lng: null, error: t.courseSearch.geo.notSupported, loading: false })
      return
    }
    // Stop any prior watch before starting a new one.
    if (watchIdRef.current != null) navigator.geolocation.clearWatch(watchIdRef.current)

    setState(s => ({ ...s, loading: true, error: null }))
    watchIdRef.current = navigator.geolocation.watchPosition(
      ({ coords }) => setState({
        lat: coords.latitude,
        lng: coords.longitude,
        error: null,
        loading: false,
      }),
      (err) => {
        // Code 1 = PERMISSION_DENIED, 2 = POSITION_UNAVAILABLE, 3 = TIMEOUT.
        const message =
          err.code === 1 ? t.courseSearch.geo.permissionDenied
          : err.code === 2 ? t.courseSearch.geo.positionUnavailable
          : err.code === 3 ? t.courseSearch.geo.timeout
          : (err.message || t.courseSearch.geo.unknown)
        setState({ lat: null, lng: null, error: message, loading: false })
      },
      WATCH_OPTIONS,
    )
  }, [t])

  useEffect(() => {
    // `start` synchronously calls setState in the "geolocation not supported" branch;
    // the watch callbacks are async and outside this concern. The lint rule can't
    // distinguish those cases — adding an explicit disable here is the simplest fix.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    start()
    return () => {
      if (watchIdRef.current != null && navigator.geolocation) {
        navigator.geolocation.clearWatch(watchIdRef.current)
      }
    }
  }, [start])

  return { ...state, request: start }
}
