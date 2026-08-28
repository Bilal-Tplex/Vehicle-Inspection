import crypto from 'node:crypto';

import { config } from '../config.js';

const { keyLength, cost, blockSize, parallelization } = config.auth.scrypt;

/**
 * Password hashing with scrypt from Node's standard library.
 *
 * No bcrypt dependency: scrypt is memory-hard, built in, and needs no native
 * compilation. The salt is generated per password and stored alongside the
 * derived key, so two identical passwords never produce the same record.
 */
export function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const derived = crypto.scryptSync(password, salt, keyLength, {
    N: cost,
    r: blockSize,
    p: parallelization,
  });
  return `${salt.toString('hex')}:${derived.toString('hex')}`;
}

/** Constant-time verification, so a wrong password cannot be timed. */
export function verifyPassword(password, stored) {
  const [saltHex, keyHex] = String(stored).split(':');
  if (!saltHex || !keyHex) return false;

  const expected = Buffer.from(keyHex, 'hex');
  const actual = crypto.scryptSync(
    password,
    Buffer.from(saltHex, 'hex'),
    expected.length,
    { N: cost, r: blockSize, p: parallelization },
  );
  return crypto.timingSafeEqual(expected, actual);
}

/** Opaque bearer token. Random, not derived from anything about the user. */
export const generateToken = () => crypto.randomBytes(32).toString('hex');

export const generateId = (prefix) =>
  `${prefix}_${crypto.randomBytes(9).toString('hex')}`;
