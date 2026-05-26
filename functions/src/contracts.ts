// Callable contract schemas — single source of truth for server-side
// validation of every onCall function in this file's sibling `index.ts`.
//
// SYNC: client mirrors these as plain TypeScript types in
// `src/types/callable.ts`. When you change a schema here, update the
// matching type on the client.

import { z } from 'zod'

// --- recordShot ---
//
// Up to 30 strokes per hole is the hard cap we accept (real games rarely
// exceed ~15; 30 is a sanity bound against runaway loops or replay attacks).
// Each club id is a short identifier (1..50 chars) — DEFAULT_BAG ids are
// short but custom user ids can be a few words long.
export const RecordShotInput = z.object({
  roundId: z.string().min(1).max(128),
  holeIndex: z.number().int().min(0).max(17),
  clubs: z.array(z.string().min(1).max(50)).max(30),
  // Whose slot to write. Optional — defaults to the caller. The host may
  // pass another participant's uid to keep score for the whole group.
  // Any non-host caller writing a foreign slot is rejected by index.ts.
  targetUid: z.string().min(1).max(128).optional(),
})
export type RecordShotInput = z.infer<typeof RecordShotInput>

// --- updateHoleConfig ---
//
// Host-only edit of par + distance for a hole. At least one of par /
// distanceMeters must be present — enforced via .refine().
export const UpdateHoleConfigInput = z
  .object({
    roundId: z.string().min(1).max(128),
    holeIndex: z.number().int().min(0).max(17),
    par: z.union([z.literal(3), z.literal(4), z.literal(5)]).optional(),
    distanceMeters: z.number().int().min(50).max(700).optional(),
  })
  .refine(v => v.par != null || v.distanceMeters != null, {
    message: 'Нечего обновлять',
  })
export type UpdateHoleConfigInput = z.infer<typeof UpdateHoleConfigInput>

// --- joinLobbyByCode ---
//
// 6-char codes drawn from the LOBBY_CHARS alphabet (no 0/O/1/I). Upper-cased
// on the server before the Firestore lookup, so we accept any case here and
// just bound the length.
//
// playerInfo is a thin, denormalised projection of AppUser used to render
// the lobby card without an extra read. Sizes match what we store on the
// round doc.
const PlayerInfoSchema = z
  .object({
    name: z.string().max(64).optional(),
    avatar: z.string().max(512).optional(),
    email: z.string().max(254).optional(),
    totalScore: z.number().int().optional(),
    scoreDiff: z.number().int().optional(),
  })
  .optional()

export const JoinLobbyInput = z.object({
  code: z.string().min(1).max(16),
  playerInfo: PlayerInfoSchema,
})
export type JoinLobbyInput = z.infer<typeof JoinLobbyInput>

// --- shareRoundByEmail ---
//
// Email validation is intentionally strict — no header-injection chars, no
// whitespace, requires one '@' and a dot in the domain. We deliberately
// reject obvious junk early so spammers get a fast 400 instead of a queued
// Resend send.
const EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
export const ShareInput = z.object({
  roundId: z.string().min(1).max(128),
  toEmail: z
    .string()
    .max(254)
    .transform(s => s.trim().toLowerCase())
    .refine(s => EMAIL_RE.test(s), { message: 'Некорректный email' }),
})
export type ShareInput = z.infer<typeof ShareInput>
