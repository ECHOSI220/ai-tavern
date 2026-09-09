import {test} from 'node:test';
import assert from 'node:assert/strict';
import {validatePackage,checksum} from '../src/package.mjs';
test('allow valid content, strip unexpected top-level data',()=>assert.deepEqual(validatePackage({schemaVersion:1,contentType:'CHARACTER_CARD',data:{name:'测试'},token:'discard'}),{schemaVersion:1,contentType:'CHARACTER_CARD',data:{name:'测试'}}));
test('reject credentials, private chats and local paths recursively',()=>{for(const data of [{apiKey:'x'},{nested:{privateChat:['x']}},{portrait:'C:\\private\\photo.png'},{authSession:{}}]) assert.throws(()=>validatePackage({schemaVersion:1,contentType:'CHARACTER_CARD',data}));});
test('allow narrative secret fields but still reject credential secrets',()=>{
 const data={secrets:['剧情秘密'],secret:'幕后设定',character_secret:'伏笔'};
 assert.deepEqual(validatePackage({schemaVersion:1,contentType:'WORLD_BOOK',data}).data,data);
 for(const sensitive of [{client_secret:'x'},{service_role_key:'x'},{openai_api_key:'x'},{access_token:'x'},{gm_secret:'x'}]) assert.throws(()=>validatePackage({schemaVersion:1,contentType:'WORLD_BOOK',data:sensitive}));
});
test('reject invalid and oversized packages',()=>{for(const x of [null,[],{}, {schemaVersion:2,contentType:'OTHER',data:{}},{schemaVersion:1,contentType:'OTHER',data:{text:'x'.repeat(2_000_001)}}]) assert.throws(()=>validatePackage(x));});
test('stable SHA256',async()=>assert.equal(await checksum('abc'),'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'));
