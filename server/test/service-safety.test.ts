import { afterEach, describe, expect, it, vi } from 'vitest';
import { campaignInputSchema, SupabaseAdmin } from '../src/services/supabase';
import { errorResponse } from '../src/utils/errors';
import type { Env } from '../src/env';

afterEach(() => vi.unstubAllGlobals());
describe('HTTP and database boundaries', () => {
  it('accepts Supabase return=minimal 201 with an empty body', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(null, { status: 201 })));
    const db = new SupabaseAdmin({ SUPABASE_URL: 'https://test.invalid', SUPABASE_SERVICE_ROLE_KEY: 'test-only' } as Env);
    await expect(db.saveCampaign('user', { title: '旅店', state: {} })).resolves.toBeNull();
  });
  it('rejects owner/revision injection and returns a safe validation error', async () => {
    const result = campaignInputSchema.safeParse({ title: '旅店', state: {}, owner_id: 'OTHER_USER_SECRET' });
    expect(result.success).toBe(false);
    if (!result.success) {
      const response = errorResponse(result.error, 'test-request');
      expect(response.status).toBe(400);
      expect(await response.text()).not.toContain('OTHER_USER_SECRET');
    }
  });
});
