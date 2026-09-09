import {afterEach,expect,it,vi} from 'vitest';
import {SupabaseAdmin} from '../src/services/supabase';
import type {Env} from '../src/env';
const env={SUPABASE_URL:'https://test.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'server-only'} as Env;
const id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',author='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
afterEach(()=>vi.unstubAllGlobals());
function mock(visibility:string,status='PUBLISHED'){
 const fetch=vi.fn(async(input:RequestInfo|URL)=>{
  const path=String(input);
  if(path.includes('/shared_contents?'))return Response.json([{author_user_id:author,visibility,status,current_version:1}]);
  if(path.includes('/shared_content_versions?'))return Response.json([{file_path:`${author}/${id}/1.json`,checksum:'c'.repeat(64),version:1}]);
  return Response.json({signedURL:`/object/sign/shared-content/${author}/${id}/1.json?token=short-lived`});
 });vi.stubGlobal('fetch',fetch);return fetch;
}
it('does not sign private content for anonymous or another user',async()=>{
 const fetch=mock('PRIVATE');
 await expect(new SupabaseAdmin(env).shareDownload(id)).rejects.toMatchObject({code:'CONTENT_NOT_FOUND'});
 await expect(new SupabaseAdmin(env).shareDownload(id,'outsider')).rejects.toMatchObject({code:'CONTENT_NOT_FOUND'});
 expect(fetch.mock.calls.every(([url])=>String(url).includes('/shared_contents?'))).toBe(true);
});
it('signs by-link unlisted content with a short TTL and no service key in output',async()=>{
 mock('UNLISTED');const result=await new SupabaseAdmin(env).shareDownload(id);
 expect(result.url).toBe(`https://test.supabase.co/storage/v1/object/sign/shared-content/${author}/${id}/1.json?token=short-lived`);
 expect(JSON.stringify(result)).not.toContain('server-only');
});
it('permits owner private download, blocks archived content for other users',async()=>{
 mock('PRIVATE');await expect(new SupabaseAdmin(env).shareDownload(id,author)).resolves.toHaveProperty('version',1);
 mock('PUBLIC','ARCHIVED');await expect(new SupabaseAdmin(env).shareDownload(id)).rejects.toMatchObject({code:'CONTENT_NOT_FOUND'});
});
