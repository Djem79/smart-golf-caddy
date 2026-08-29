import type { RoundLike } from './buildPayload'

// shareRoundByEmail (../index.ts) always renders the CALLER's own uid's
// round performance, but the *recipient* — whose locale actually decides
// the email's language — is identified only by the target email address
// (it may be the caller forwarding their own summary to a teammate's
// inbox, not necessarily the caller's own address). This maps that address
// back to a participant uid so the caller can look up *that* uid's
// users/{uid}.locale, instead of defaulting to the content owner's locale.
//
// Pure and Firestore-free on purpose — the permission check in
// shareRoundByEmail already guarantees targetEmail is either the caller's
// own auth email or a recorded participant email, so this only needs to
// pick which one it was, not re-validate.
export function findRecipientUid(
  round: Pick<RoundLike, 'players'>,
  callerUid: string,
  callerEmail: string,
  targetEmail: string,
): string | undefined {
  const target = targetEmail.toLowerCase()
  if (callerEmail.toLowerCase() === target) return callerUid
  for (const [uid, player] of Object.entries(round.players ?? {})) {
    if ((player?.email ?? '').toLowerCase() === target) return uid
  }
  return undefined
}
