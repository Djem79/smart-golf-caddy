import { getFunctions, httpsCallable } from 'firebase/functions'
import { app } from '../firebase'
import type { DeleteAccountInput, DeleteAccountResult } from '../types/callable'

// Cloud Functions are deployed to us-central1 (see functions/src/index.ts).
const functions = getFunctions(app, 'us-central1')

const deleteAccountCallable = httpsCallable<DeleteAccountInput, DeleteAccountResult>(
  functions,
  'deleteAccount',
)

// Permanently deletes the caller's account: profile, quota counters, green
// marks, solo rounds, group-round membership is anonymized to "Удалённый
// игрок", and finally the Firebase Auth record itself (server-side, see
// functions/src/index.ts:deleteAccount). Payload is empty by contract — the
// server always derives the uid from the verified auth token.
//
// This does NOT sign the client out — the caller (Profile screen) is
// responsible for that, so a failed deletion never leaves the user logged
// out with data that may not have actually been removed.
export async function deleteAccount(): Promise<void> {
  await deleteAccountCallable({})
}
