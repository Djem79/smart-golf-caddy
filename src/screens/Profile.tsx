import { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Briefcase, ChevronRight, ExternalLink, Trash2 } from 'lucide-react'
import { useAuth } from '../hooks/useAuth'
import { useProfile } from '../hooks/useProfile'
import { signOut, isAppleLinked, revokeAppleAccess, isPopupCancelled } from '../services/auth'
import { getUserRounds } from '../services/rounds'
import { deleteAccount } from '../services/account'
import { updateLocale } from '../services/users'
import { computeClubUsage, computePlayerStats, computeHandicap } from '../services/scoring'
import { getBagFromUser, getClubLabel, scoreColor } from '../types'
import type { Round } from '../types'
import { Button } from '../components/ui/Button'
import { Card } from '../components/ui/Card'
import { Avatar } from '../components/ui/Avatar'
import { ConfirmDialog } from '../components/ui/ConfirmDialog'
import { PageHeader } from '../components/layout/PageHeader'
import { BottomNav } from '../components/layout/BottomNav'
import { useT, plural, setLocale, type Locale } from '../i18n'

export function Profile() {
  const navigate = useNavigate()
  const { user } = useAuth()
  const { profile } = useProfile()
  const { t, locale } = useT()

  // Public static site pages (App Store 5.1.1(v) — privacy, terms, and
  // support must be reachable from inside the app). One domain — updating
  // the address if we move to our own domain happens in one place.
  const LEGAL_LINKS = [
    { label: t.profile.privacyPolicy, href: 'https://smart-golf-caddy.web.app/privacy' },
    { label: t.profile.termsOfUse, href: 'https://smart-golf-caddy.web.app/terms' },
    { label: t.profile.support, href: 'https://smart-golf-caddy.web.app/support' },
  ] as const
  const [signingOut, setSigningOut] = useState(false)
  const [rounds, setRounds] = useState<Round[]>([])
  const [loadError, setLoadError] = useState(false)
  const [reloadKey, setReloadKey] = useState(0)
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [deletingAccount, setDeletingAccount] = useState(false)
  const [deleteError, setDeleteError] = useState<string | null>(null)

  const bag = useMemo(() => getBagFromUser(profile), [profile])

  useEffect(() => {
    if (!user) return
    let cancelled = false
    // eslint-disable-next-line react-hooks/set-state-in-effect -- clears stale error before refetching; the async result-handlers set the next value via .then/.catch
    setLoadError(false)
    getUserRounds(user.uid)
      .then(all => { if (!cancelled) setRounds(all) })
      .catch(() => { if (!cancelled) setLoadError(true) })
    return () => { cancelled = true }
  }, [user, reloadKey])

  const stats = useMemo(
    () => user ? computePlayerStats(rounds, user.uid) : null,
    [rounds, user],
  )

  const handicap = useMemo(
    () => user ? computeHandicap(rounds, user.uid) : null,
    [rounds, user],
  )

  const clubStats = useMemo(
    () => user ? computeClubUsage(rounds, user.uid).slice(0, 5) : [],
    [rounds, user],
  )

  async function handleSignOut() {
    setSigningOut(true)
    try {
      await signOut()
      navigate('/auth', { replace: true })
    } catch {
      setSigningOut(false)
    }
  }

  // Switches immediately via setLocale (every useT() subscriber re-renders
  // in place — no reload) and persists to the profile so it's picked up on
  // other devices too. Firestore write failure is non-critical: the UI
  // already reflects the choice, same pattern as changeUnits in MyBag.tsx.
  async function changeLanguage(l: Locale) {
    if (l === locale) return
    setLocale(l)
    if (!user) return
    try { await updateLocale(user.uid, l) } catch { /* non-critical */ }
  }

  async function handleDeleteAccount() {
    setDeletingAccount(true)
    setDeleteError(null)
    // Apple TN3194: a Sign in with Apple token MUST be revoked when the
    // account is deleted. It needs a fresh Apple re-authentication (popup),
    // so it runs first, straight from the confirm click, and the account is
    // left untouched if it doesn't go through — the user can retry.
    if (user && isAppleLinked(user)) {
      try {
        await revokeAppleAccess(user)
      } catch (e) {
        setShowDeleteConfirm(false)
        setDeletingAccount(false)
        // Closing the Apple popup = changed their mind, not an error.
        if (!isPopupCancelled(e)) setDeleteError(t.profile.appleRevokeError)
        return
      }
    }
    try {
      // Server deletes the Firestore profile/data first, Firebase Auth
      // record last (see functions/src/index.ts:deleteAccount). Sign out
      // immediately on success so the profile subscription tears down
      // before the now-invalid session could surface a stray
      // permission-denied from a live Firestore listener.
      await deleteAccount()
      setShowDeleteConfirm(false)
      await signOut()
      navigate('/auth', { replace: true })
    } catch {
      // Deletion may have failed partway — never sign the user out on
      // error, they may still need to retry.
      setShowDeleteConfirm(false)
      setDeletingAccount(false)
      setDeleteError(t.profile.deleteAccountError)
    }
  }

  const maxClubCount = clubStats[0]?.count ?? 0
  const totalHoles = stats?.totalHolesPlayed ?? 0
  const pct = (n: number) => totalHoles > 0 ? Math.round((n / totalHoles) * 100) : 0

  return (
    <div className="screen pb-20">
      <PageHeader title={t.profile.title} showBack={false} />

      <div className="flex-1 px-5 pt-5 space-y-5 overflow-y-auto">
        {loadError && (
          <div className="bg-error-container/40 border border-error/30 rounded-lg px-4 py-3 flex items-center justify-between gap-3">
            <p className="text-label-lg text-on-surface">{t.profile.loadError}</p>
            <button
              type="button"
              onClick={() => setReloadKey(k => k + 1)}
              className="text-label-lg font-semibold text-primary underline-offset-4 hover:underline shrink-0"
            >
              {t.common.retry}
            </button>
          </div>
        )}
        <Card>
          <div className="flex items-center gap-4">
            <Avatar src={user?.photoURL} name={user?.displayName} size={64} />
            <div className="min-w-0 flex-1">
              <p className="font-headline font-bold text-title-lg text-on-surface truncate tracking-tight">
                {user?.displayName ?? t.home.fallbackName}
              </p>
              <p className="text-label-lg text-on-surface-variant truncate">{user?.email ?? ''}</p>
            </div>
          </div>
        </Card>

        {/* Language switcher — a settings pill, not an action button; same
            visual pattern as the units toggle in MyBag.tsx. */}
        <div className="flex flex-col items-center gap-2">
          <p className="text-label-md text-on-surface-variant uppercase tracking-wider">{t.profile.language}</p>
          <div className="inline-flex p-1 bg-surface-container rounded-lg">
            {(['ru', 'en'] as const).map(l => (
              <button
                key={l}
                type="button"
                onClick={() => changeLanguage(l)}
                className={`px-6 py-2 rounded-md text-label-lg font-semibold transition-colors min-h-touch ${
                  locale === l
                    ? 'bg-surface-container-lowest text-primary shadow-card'
                    : 'text-on-surface-variant'
                }`}
              >
                {l === 'ru' ? t.profile.languageRu : t.profile.languageEn}
              </button>
            ))}
          </div>
        </div>

        {/* Stats summary: rounds / avg / best / all-time best (only matters if played) */}
        <Card>
          <h3 className="font-headline font-semibold text-title-lg text-on-surface">{t.profile.stats}</h3>
          {stats && stats.roundsPlayed > 0 ? (
            <div className="grid grid-cols-2 gap-4 mt-3">
              <div>
                <p className="text-label-md text-on-surface-variant uppercase tracking-wider">{t.profile.rounds}</p>
                <p className="font-headline font-bold text-headline-md text-primary mt-1">{stats.roundsPlayed}</p>
              </div>
              <div>
                <p className="text-label-md text-on-surface-variant uppercase tracking-wider">{t.profile.avgShots}</p>
                <p className="font-headline font-bold text-headline-md text-primary mt-1">{stats.avgShots.toFixed(stats.avgShots % 1 === 0 ? 0 : 1)}</p>
              </div>
              <div>
                <p className="text-label-md text-on-surface-variant uppercase tracking-wider">{t.profile.bestScore}</p>
                <p className="font-headline font-bold text-headline-md text-primary mt-1">{stats.bestScore}</p>
              </div>
              <div>
                <p className="text-label-md text-on-surface-variant uppercase tracking-wider">{t.profile.bestVsPar}</p>
                <p className="font-headline font-bold text-headline-md text-primary mt-1">
                  {stats.bestScoreDiff != null
                    ? (stats.bestScoreDiff > 0 ? `+${stats.bestScoreDiff}` : stats.bestScoreDiff)
                    : '—'}
                </p>
              </div>
            </div>
          ) : (
            <p className="text-label-lg text-on-surface-variant mt-2">
              {t.profile.noStatsYet}
            </p>
          )}
        </Card>

        {/* Hole result distribution — only render when there are holes to summarize */}
        {stats && stats.totalHolesPlayed > 0 && (
          <Card>
            <h3 className="font-headline font-semibold text-title-lg text-on-surface">{t.profile.holeDistribution}</h3>
            <p className="text-label-md text-on-surface-variant mt-1">
              {t.profile.overAllHoles(stats.totalHolesPlayed, plural(stats.totalHolesPlayed, locale, t.profile.playedHolesWord))}
            </p>
            {/* Stacked bar */}
            <div className="flex h-3 w-full rounded-full overflow-hidden mt-3 bg-surface-container">
              {([
                ['eagle',  stats.holeStats.eagle,  scoreColor(-2)],
                ['birdie', stats.holeStats.birdie, scoreColor(-1)],
                ['par',    stats.holeStats.par,    scoreColor(0)],
                ['bogey',  stats.holeStats.bogey,  scoreColor(1)],
                ['double', stats.holeStats.double, scoreColor(2)],
                ['worse',  stats.holeStats.worse,  scoreColor(3)],
              ] as const).map(([key, count, color]) => count > 0 && (
                <div
                  key={key}
                  style={{ width: `${pct(count)}%`, backgroundColor: color }}
                  className="h-full"
                  title={`${key}: ${count}`}
                />
              ))}
            </div>
            {/* Legend */}
            <div className="grid grid-cols-3 gap-y-2 gap-x-3 mt-3">
              {([
                { key: 'eagle',  label: 'Eagle+',  count: stats.holeStats.eagle,  color: scoreColor(-2) },
                { key: 'birdie', label: 'Birdie',  count: stats.holeStats.birdie, color: scoreColor(-1) },
                { key: 'par',    label: 'Par',     count: stats.holeStats.par,    color: scoreColor(0) },
                { key: 'bogey',  label: 'Bogey',   count: stats.holeStats.bogey,  color: scoreColor(1) },
                { key: 'double', label: 'Double',  count: stats.holeStats.double, color: scoreColor(2) },
                { key: 'worse',  label: t.profile.worseLabel, count: stats.holeStats.worse,  color: scoreColor(3) },
              ]).map(item => (
                <div key={item.key} className="flex items-center gap-2 min-w-0">
                  <span
                    className="w-3 h-3 rounded-sm shrink-0 border border-outline-variant/30"
                    style={{ backgroundColor: item.color }}
                  />
                  <div className="min-w-0 flex-1">
                    <p className="text-label-md text-on-surface font-semibold truncate">{item.label}</p>
                    <p className="text-label-md text-on-surface-variant">
                      {item.count} · {pct(item.count)}%
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </Card>
        )}

        <Card>
          <h3 className="font-headline font-semibold text-title-lg text-on-surface">{t.profile.handicap}</h3>
          {handicap ? (
            <>
              <p className="font-headline font-bold text-display-lg text-primary mt-2">
                {handicap.index >= 0 ? handicap.index.toFixed(1) : `+${Math.abs(handicap.index).toFixed(1)}`}
              </p>
              <p className="text-label-md text-on-surface-variant">
                {handicap.bestUsed === 8
                  ? t.profile.handicapBest8(handicap.basedOnRounds)
                  : t.profile.handicapAvg(handicap.basedOnRounds, plural(handicap.basedOnRounds, locale, t.profile.roundsWord))
                }
              </p>
            </>
          ) : (
            <p className="text-label-lg text-on-surface-variant mt-1">
              {t.profile.handicapEmpty}
            </p>
          )}
        </Card>

        <Card>
          <h3 className="font-headline font-semibold text-title-lg text-on-surface">{t.profile.favoriteClubs}</h3>
          {clubStats.length === 0 ? (
            <p className="text-label-lg text-on-surface-variant mt-2">
              {t.profile.favoriteClubsEmpty}
            </p>
          ) : (
            <div className="space-y-2.5 mt-3">
              {clubStats.map(({ club, count, percent }) => (
                <div key={club}>
                  <div className="flex items-center justify-between mb-1">
                    <span className="font-semibold text-body-md text-on-surface">{getClubLabel(club, bag, t.common.clubLabels)}</span>
                    <span className="text-label-md text-on-surface-variant">
                      {count} {plural(count, locale, t.profile.shotsWord)} · {percent}%
                    </span>
                  </div>
                  <div className="h-2 bg-surface-container rounded-full overflow-hidden">
                    <div
                      className="h-full bg-primary rounded-full"
                      style={{ width: `${(count / maxClubCount) * 100}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>
          )}
        </Card>

        <button
          type="button"
          onClick={() => navigate('/bag')}
          className="w-full text-left rounded-lg overflow-hidden bg-gradient-to-br from-primary-container to-primary text-on-primary p-5 active:scale-[0.995] transition-transform shadow-card"
        >
          <div className="flex items-center gap-3">
            <div className="w-11 h-11 rounded-md bg-on-primary/15 flex items-center justify-center shrink-0">
              <Briefcase size={20} strokeWidth={1.75} />
            </div>
            <p className="font-headline font-semibold text-label-lg uppercase tracking-[0.18em]">
              {t.profile.myBag}
            </p>
          </div>
          <div className="flex items-center justify-between mt-4">
            <p className="text-body-md text-on-primary/85">
              {t.profile.bagSummary(
                bag.filter(c => c.enabled).length,
                plural(bag.filter(c => c.enabled).length, locale, t.common.clubsWord),
                profile?.units === 'yd' ? t.myBag.yardsUnitWord : t.myBag.metersUnitWord,
              )}
            </p>
            <ChevronRight size={20} strokeWidth={1.75} />
          </div>
        </button>

        {/* Legal / support links — deliberately separated from the
            sign-out/delete-account buttons so they aren't mis-tapped next to
            a destructive action. Open in an external tab. */}
        <nav aria-label={t.profile.legalLinksAria} className="pt-2 border-t border-outline-variant/30 space-y-1">
          {LEGAL_LINKS.map(link => (
            <a
              key={link.href}
              href={link.href}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-2 min-h-touch px-1 text-label-lg text-on-surface-variant hover:text-on-surface transition-colors"
            >
              <ExternalLink size={16} strokeWidth={1.75} className="shrink-0" />
              {link.label}
            </a>
          ))}
        </nav>

        <Button variant="secondary" onClick={handleSignOut} disabled={signingOut}>
          {signingOut ? t.profile.signingOut : t.profile.signOut}
        </Button>

        <div className="pt-2 space-y-2 border-t border-outline-variant/30">
          {deleteError && (
            <p className="text-label-lg text-error text-center">{deleteError}</p>
          )}
          <Button
            variant="danger"
            icon={Trash2}
            onClick={() => setShowDeleteConfirm(true)}
            disabled={deletingAccount}
            className="mt-3"
          >
            {t.profile.deleteAccount}
          </Button>
        </div>
      </div>

      <BottomNav />

      <ConfirmDialog
        open={showDeleteConfirm}
        title={t.profile.deleteConfirmTitle}
        body={t.profile.deleteConfirmBody}
        confirmLabel={t.profile.delete}
        cancelLabel={t.common.cancel}
        destructive
        loading={deletingAccount}
        onConfirm={handleDeleteAccount}
        onCancel={() => setShowDeleteConfirm(false)}
      />
    </div>
  )
}
