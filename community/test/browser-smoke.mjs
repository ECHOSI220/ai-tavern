import {chromium} from '@playwright/test';
import assert from 'node:assert/strict';
const browser=await chromium.launch({headless:true,...(process.env.PW_CHANNEL?{channel:process.env.PW_CHANNEL}:{})});
const base=process.env.WEB_TEST_URL??'https://ai-tavern-cloud.pages.dev';
try{
 for(const width of [320,375,430,768,1440]){
  const page=await browser.newPage({viewport:{width,height:900}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(base,{waitUntil:'networkidle'});await page.getByRole('heading',{name:'探索灵感'}).waitFor();
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`overflow at ${width}`);
  await page.screenshot({path:`test-results/home-${width}.png`,fullPage:true});
  await page.goto(base+'/login',{waitUntil:'networkidle'});await page.getByLabel('邮箱',{exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  await page.goto(base+'/me/uploads',{waitUntil:'networkidle'});await page.getByLabel('邮箱',{exact:true}).waitFor();
  await page.goto(base+'/downloads',{waitUntil:'networkidle'});await page.getByRole('heading',{name:'下载 AI 酒馆',exact:true}).waitFor();
  await page.getByRole('heading',{name:'Windows',exact:true}).waitFor();
  await page.getByRole('heading',{name:'Android',exact:true}).waitFor();
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,`download overflow at ${width}`);
  await page.screenshot({path:`test-results/downloads-${width}.png`,fullPage:true});
  assert.deepEqual(errors,[]);await page.close();
 }
 console.log('PASS live homepage/login/protected uploads at 320,375,430,768,1440px; no horizontal overflow or page exceptions');
}finally{await browser.close();}
