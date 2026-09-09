export const types = {CHARACTER_CARD:'角色卡', WORLD_BOOK:'世界书', CAMPAIGN_TEMPLATE:'剧本', THEME_PACK:'皮肤', RULE_PACK:'规则', PROMPT_PACK:'提示词', OTHER:'其他'};
const exactSensitiveKeys = new Set(['password','passwd','credential','credentials','authorization','bearer','accesstoken','refreshtoken','idtoken','clientsecret','privatechat','privateroll','gmsecret','messagehistory','localpath','sessiontoken','sessionid','authsession']);
const isSensitiveKey=(key)=>{
  const normalized=String(key).toLowerCase().replace(/[^a-z0-9]/g,'');
  return exactSensitiveKeys.has(normalized) || /(?:api|access|secret)key$/.test(normalized) || /^servicerole(?:key)?$/.test(normalized);
};
// Reject, never silently publish secrets hidden inside arbitrary imported JSON.
export function validatePackage(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input) || input.schemaVersion !== 1 || !Object.hasOwn(types,input.contentType)) throw Error('只接受 schemaVersion=1 的 Tavern SharePackage。');
  if (!input.data || typeof input.data !== 'object' || Array.isArray(input.data)) throw Error('分享包缺少 data 对象。');
  const walk=(value, depth=0)=>{
    if(depth>32) throw Error('分享包嵌套过深。');
    if(typeof value==='string' && (/^(file:|[a-z]:\\|\/Users\/|\/home\/)/i.test(value) || /\b(?:sk-[a-z0-9]{16,}|eyJ[a-zA-Z0-9_-]+\.eyJ[a-zA-Z0-9_-]+\.)/.test(value))) throw Error('内容含本地路径或疑似密钥，请清理后重试。');
    if(value && typeof value==='object') for(const [key,child] of Object.entries(value)) {
      if(isSensitiveKey(key) || ['__proto__','constructor','prototype'].includes(key)) throw Error('分享包含账号或隐私敏感字段：'+key);
      walk(child,depth+1);
    }
  };
  walk(input.data);
  const clean={schemaVersion:1,contentType:input.contentType,data:input.data};
  if(new TextEncoder().encode(JSON.stringify(clean)).length>2_000_000) throw Error('JSON 分享包不能超过 2 MB。');
  return clean;
}
export async function checksum(text) {return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text)))].map(v=>v.toString(16).padStart(2,'0')).join('');}

// Ordinary exported JSON stays intact inside data; the user explicitly chooses its type.
export function prepareUpload(input, selectedType) {
  if (!input || typeof input !== 'object') throw Error('JSON 必须是对象或条目数组。');
  if (Object.hasOwn(input,'schemaVersion') && Object.hasOwn(input,'contentType')) {
    return {pack:validatePackage(input), converted:false};
  }
  if (!Object.hasOwn(types,selectedType)) throw Error('普通 JSON 请先选择内容类型，例如世界书。');
  const data=Array.isArray(input)?{entries:input}:input;
  return {pack:validatePackage({schemaVersion:1,contentType:selectedType,data}),converted:true};
}
