import { getFunctions, httpsCallable } from 'firebase/functions'
import { app } from '../firebase'
import type { ShareInput, ShareResult } from '../types/callable'

// Cloud Functions are deployed to us-central1 (see functions/src/index.ts).
const functions = getFunctions(app, 'us-central1')

const shareRoundCallable = httpsCallable<ShareInput, ShareResult>(
  functions,
  'shareRoundByEmail',
)

export async function shareRoundByEmail(roundId: string, toEmail: string): Promise<void> {
  await shareRoundCallable({ roundId, toEmail })
}
