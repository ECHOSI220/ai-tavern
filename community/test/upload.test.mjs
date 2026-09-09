import {test} from 'node:test';
import assert from 'node:assert/strict';
import {prepareUpload} from '../src/package.mjs';
test('ordinary worldbook keeps every entry and converts without editing source',()=>{
 const source={entries:{'0':{key:['魔法'],content:'世界设定',enabled:true,secrets:['剧情伏笔']}}};
 const result=prepareUpload(source,'WORLD_BOOK');
 assert.equal(result.converted,true);assert.equal(result.pack.contentType,'WORLD_BOOK');
 assert.deepEqual(result.pack.data,source);assert.equal(source.schemaVersion,undefined);
});
test('entry arrays and character-card v2 exports are supported',()=>{
 assert.deepEqual(prepareUpload([{content:'设定'}],'WORLD_BOOK').pack.data,{entries:[{content:'设定'}]});
 const card={spec:'chara_card_v2',data:{name:'角色',description:'设定'}};
 assert.deepEqual(prepareUpload(card,'CHARACTER_CARD').pack.data,card);
});
test('conversion still rejects credentials, private history and malformed packages',()=>{
 for(const source of [{api_key:'private'},{privateChat:['private']},{schemaVersion:2,contentType:'WORLD_BOOK',data:{}}]) assert.throws(()=>prepareUpload(source,'WORLD_BOOK'));
 assert.throws(()=>prepareUpload({entries:[]},''));
 assert.throws(()=>prepareUpload('text','OTHER'));
});
