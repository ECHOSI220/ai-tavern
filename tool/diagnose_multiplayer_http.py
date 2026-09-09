import ctypes as ct, json, sqlite3, subprocess
from pathlib import Path
root=Path('C:/Users/私塾童鞋/AppData/Roaming/com.imaginary.tavern/AI Tavern - 幻境酒馆')
class Blob(ct.Structure):
    _fields_=[('size',ct.c_ulong),('data',ct.POINTER(ct.c_ubyte))]
encrypted=(root/'flutter_secure_storage.dat').read_bytes()
buffer=(ct.c_ubyte*len(encrypted)).from_buffer_copy(encrypted)
source=Blob(len(encrypted),buffer); target=Blob()
if not ct.windll.crypt32.CryptUnprotectData(ct.byref(source),None,None,None,None,0,ct.byref(target)):
    raise RuntimeError('Cannot access app credential storage')
try: secrets=json.loads(ct.string_at(target.data,target.size))
finally: ct.windll.kernel32.LocalFree(target.data)
db=sqlite3.connect('file:'+str(root/'ai_tavern.db')+'?mode=ro',uri=True)
profiles=[json.loads(row[0]) for row in db.execute('select payload from api_profiles')]
profile=next(p for p in profiles if p['model']=='deepseek-v4-flash')
key=secrets['api_profile_key_'+profile['id']]
tools=[{'type':'function','function':{'name':'advance_time','description':'请求服务器执行并验证规则操作。以工具返回结果为准。','parameters':{'$schema':'https://json-schema.org/draft/2020-12/schema','type':'object','properties':{'minutes':{'type':'integer','minimum':0,'maximum':1440}},'required':['minutes'],'additionalProperties':False}}}]
tests=[]
for name,size in [('multiplayer-tool-roundtrip',1500)]:
    tests.append({'name':name,'body':{'model':profile['model'],'messages':[{'role':'user','content':'Call advance_time with minutes 5, then briefly confirm completion. Ignore the following padding: '+'玩家调查房间。'*size}],'temperature':0.9,'top_p':1.0,'max_tokens':2000,'stream':False,'tools':tools,'tool_choice':'auto'}})
result=subprocess.run(['D:/AI_Tavern_Tools/flutter/bin/dart.bat','run','tool/diagnose_multiplayer_http.dart'],input=json.dumps({'key':key,'tests':tests,'proxy':True}),encoding='utf-8',cwd='D:/AI_Tavern_Project',capture_output=True)
print(result.stdout.replace(key,'[redacted]'))
if result.returncode: print('Diagnostic process failed',result.returncode)
