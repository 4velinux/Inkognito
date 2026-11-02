/* Development-only browser checks. See tests/README.md for the external harness. */
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { chromium } = require(process.env.INKOGNITO_PLAYWRIGHT || 'playwright-core');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
let tempDir; const requests = [], errors = [];
let browser, page;
before(async () => {
  browser = await chromium.launch({ executablePath: process.env.INKOGNITO_CHROMIUM, headless: true });
  page = await browser.newPage({ viewport: { width: 1440, height: 1100 }, acceptDownloads: true });
  page.setDefaultTimeout(5000);
  page.on('request', r => { if (/^https?:/.test(r.url())) requests.push(r.url()); });
  page.on('pageerror', e => errors.push(e.message));
  tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'inkognito-media-'));
  const source = fs.readFileSync(path.resolve(__dirname, '../inkognito.html'), 'utf8');
  // The dashboard adapter lives inside this same IIFE. Export only its agreed seam in the temporary test copy.
  const hooked = source.replace("window.addEventListener('beforeunload',saveNow);", "window.addEventListener('beforeunload',saveNow); window.mediaTest={setPreviewMedia,openMediaViewer,cardHTML,setMediaViewerNavigation:typeof setMediaViewerNavigation==='function'?setMediaViewerNavigation:null};");
  assert.notEqual(hooked, source);
  fs.writeFileSync(path.join(tempDir, 'inkognito.html'), hooked);
  await page.goto('file://' + path.join(tempDir, 'inkognito.html'));
});
after(async () => { if (browser) await browser.close(); if(tempDir) fs.rmSync(tempDir, { recursive: true, force: true }); });
async function fixture(name, width, height) {
  const data = await page.evaluate(({ width, height }) => {
    const c = document.createElement('canvas'); c.width = width; c.height = height;
    const g = c.getContext('2d'); g.fillStyle = '#1266aa'; g.fillRect(0, 0, width, height);
    g.fillStyle = '#ffcc55'; g.fillRect(0, 0, width / 2, height / 2);
    return c.toDataURL('image/png').split(',')[1];
  }, { width, height });
  return { name, mimeType: 'image/png', buffer: Buffer.from(data, 'base64') };
}
test('ordered image picking renders two photos and reordering changes the lead', async () => {
  await page.locator('#imgIn').setInputFiles([await fixture('wide.png', 900, 300), await fixture('tall.png', 300, 600)]);
  await page.waitForFunction(() => document.querySelectorAll('#cardDesk [data-media-index]').length === 2);
  assert.equal(await page.locator('#cardDesk [data-media-index] img').first().getAttribute('alt'), 'wide.png');
  await page.getByRole('button', { name: 'Move image 2 earlier' }).click();
  assert.equal(await page.locator('#cardDesk [data-media-index] img').first().getAttribute('alt'), 'tall.png');
  assert.equal(await page.locator('#cardMob [data-media-index]').count(), 2);
});
test('image inspection shows original fit, navigates, zooms and returns keyboard focus', async () => {
  const tile = page.locator('#cardDesk [data-media-index="0"]');
  await tile.focus(); await page.keyboard.press('Enter');
  assert.equal(await page.locator('#mediaViewer[open]').count(), 1, 'image activation opens the original viewer');
  assert.equal(await page.locator('#viewerImage').getAttribute('alt'), 'tall.png');
  assert.equal(await page.locator('#viewerCount').textContent(), '1 / 2');
  await page.keyboard.press('ArrowRight');
  assert.equal(await page.locator('#viewerImage').getAttribute('alt'), 'wide.png');
  await page.getByRole('button', { name: 'Zoom to original size', exact: true }).click();
  assert.equal(await page.locator('#viewerZoom').getAttribute('aria-pressed'), 'true');
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('#mediaViewer[open]').count(), 0);
  assert.equal(await tile.evaluate(el => el === document.activeElement), true);
  assert.equal(await page.locator('#cardDesk [data-media-index]').count(), 2);
});
test('image descriptions retain quotes without becoming markup', async () => {
  await page.getByRole('textbox', { name: 'Image 1 description', exact: true }).fill('Architecture "A" <B>');
  await page.getByRole('textbox', { name: 'Image 1 description', exact: true }).press('Tab');
  assert.equal(await page.locator('#cardDesk [data-media-index="0"] img').getAttribute('alt'), 'Architecture "A" <B>');
});
test('two images share height while keeping their supported individual aspect ratios', async () => {
  const boxes = await page.evaluate(() => Array.from(document.querySelectorAll('#cardDesk [data-media-index]')).map(el => ({ width: el.clientWidth, height: el.clientHeight })));
  // Current order is 1:2 (clamped to4:5) then3:1. Expected width ratio .8/3.
  assert.ok(Math.abs(boxes[0].width / boxes[1].width - .8 / 3) < .02);
});
test('changing draft clears transient images and closes original inspection', async () => {
  await page.locator('#cardDesk [data-media-index="0"]').click();
  // A new draft is a different post; images must never silently follow it.
  await page.keyboard.press('Escape');
  await page.locator('[data-pop="p-drafts"]').click();
  await page.getByRole('button', { name: 'New draft', exact: true }).click();
  assert.equal(await page.locator('#cardDesk [data-media-index]').count(), 0);
  assert.equal(await page.locator('#mediaViewer[open]').count(), 0);
});

test('expanded inspection keeps the current post copy as context', async () => {
  await page.evaluate(() => window.mediaTest.setPreviewMedia([]));
  await page.locator('#ta').fill('Synthetic post context.\n\nThe original remains unchanged.');
  await page.locator('#imgIn').setInputFiles(await fixture('context.png', 500, 400));
  await page.waitForFunction(() => document.querySelectorAll('#cardDesk [data-media-index]').length === 1);
  await page.locator('#cardDesk [data-media-index="0"]').click();
  assert.equal(await page.locator('#viewerPost').count(), 1);
  assert.ok(await page.locator('#viewerPost .li-head').count());
  assert.match(await page.locator('#viewerPost .li-text').textContent(),/Synthetic post context/);
  if(process.env.INKOGNITO_SCREENSHOTS) await page.locator('#mediaViewer').screenshot({path:path.join(process.env.INKOGNITO_SCREENSHOTS,'inkognito-original-desktop.png')});
  await page.keyboard.press('Escape');
});

test('gallery orientation, overflow, supported crop and image-free serialization use shared media', async () => {
  const data = 'data:image/png;base64,' + (await fixture('fixture.png', 80, 80)).buffer.toString('base64');
  const wide='data:image/png;base64,'+(await fixture('wide.png',240,80)).buffer.toString('base64');
  const records = Array.from({ length:20 }, (_,i) => ({ id:String(i),src:i===0?wide:data,alt:'Image '+i,width:i===0?240:80,height:80 }));
  assert.equal(await page.evaluate(items => window.mediaTest.setPreviewMedia(items), records), true);
  assert.equal(await page.locator('#cardDesk .li-gallery.landscape').count(), 1);
  assert.equal(await page.locator('#cardDesk [data-media-index]').count(), 5);
  assert.equal(await page.locator('#cardDesk .li-overflow').textContent(), '+15');
  if(process.env.INKOGNITO_SCREENSHOTS) await page.locator('#cardDesk').screenshot({path:path.join(process.env.INKOGNITO_SCREENSHOTS,'inkognito-gallery-desktop.png')});
  const positions = await page.evaluate(() => Array.from(document.querySelectorAll('#cardDesk [data-media-index]')).map(el => ({x:el.offsetLeft,y:el.offsetTop,w:el.clientWidth,h:el.clientHeight})));
  assert.ok(positions[0].w > positions[1].w*2 && positions[1].y > positions[0].y);
  for(const n of [3,4,5]){await page.evaluate(items=>window.mediaTest.setPreviewMedia(items),records.slice(0,n));assert.equal(await page.locator('#cardDesk [data-media-index]').count(),n);}
  assert.equal(await page.evaluate(items => window.mediaTest.setPreviewMedia(items), records.slice(1,4)), true);
  assert.equal(await page.locator('#cardDesk .li-gallery.portrait').count(), 1);
  const vertical = await page.evaluate(() => Array.from(document.querySelectorAll('#cardDesk [data-media-index]')).map(el => ({x:el.offsetLeft,y:el.offsetTop,w:el.clientWidth,h:el.clientHeight})));
  assert.ok(vertical[0].h > vertical[1].h && vertical[1].x > vertical[0].x);
  for (const [width,height,ratio] of [[100,1000,.8],[1000,100,3],[500,500,1]]) {
    const src='data:image/png;base64,'+(await fixture('ratio.png',width,height)).buffer.toString('base64');
    await page.evaluate(item => window.mediaTest.setPreviewMedia([item]), {...records[0],src,width,height});
    const box = await page.evaluate(()=>{const rect=document.querySelector('#cardDesk .li-gallery').getBoundingClientRect();return {width:rect.width,height:rect.height};});
    assert.ok(Math.abs(box.width/box.height-ratio)<.01);
  }
  const snapshot = await page.evaluate(() => window.mediaTest.cardHTML('desk','Saved text',true));
  assert.ok(snapshot.includes('Saved text')); assert.ok(!/data:image|blob:|li-gallery/.test(snapshot));
});
test('invalid and oversized image selections preserve the previous gallery', async () => {
  const original = await page.locator('#cardDesk [data-media-index="0"]').getAttribute('data-media-id');
  await page.locator('#imgIn').setInputFiles({ name:'broken.png',mimeType:'image/png',buffer:Buffer.from('not an image') });
  await page.waitForFunction(() => document.querySelector('#mediaNotice').textContent.includes('could not be decoded'));
  assert.equal(await page.locator('#cardDesk [data-media-index="0"]').getAttribute('data-media-id'), original);
  const data = 'data:image/png;base64,' + (await fixture('fixture.png',80,80)).buffer.toString('base64');
  const valid = {id:'valid',src:data,alt:'Valid',width:80,height:80};
  for (const invalid of [Array.from({length:21},(_,i)=>({...valid,id:String(i)})),[{...valid,src:'https://example.invalid/image.png'}],[{...valid,width:0}],[{...valid,width:10000,height:10000}],[{...valid,width:6000,height:6000},{...valid,id:'2',width:6000,height:6000},{...valid,id:'3',width:6000,height:6000}],[valid,valid]]) {
    assert.equal(await page.evaluate(items => window.mediaTest.setPreviewMedia(items), invalid), false);
    assert.equal(await page.locator('#cardDesk [data-media-index="0"]').getAttribute('data-media-id'), original);
  }
});
test('viewer survives feed rerender, closes on removal and releases focus', async () => {
  const source = 'data:image/png;base64,' + (await fixture('focus.png',400,300)).buffer.toString('base64');
  const item={id:'focus',src:source,alt:'Focus',width:400,height:300};
  await page.evaluate(item => { window.viewerEvents=[]; document.addEventListener('inkognito:viewer', e => window.viewerEvents.push(e.detail.open)); window.mediaTest.setPreviewMedia([item]); },item);
  await page.locator('#cardDesk [data-media-index="0"]').focus(); await page.keyboard.press('Enter');
  await page.evaluate(item => window.mediaTest.setPreviewMedia([item]),item);
  assert.equal(await page.locator('#mediaViewer[open]').count(),1);
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('#cardDesk [data-media-index="0"]').evaluate(el => el===document.activeElement),true);
  await page.keyboard.press('Enter');
  await page.evaluate(() => window.mediaTest.setPreviewMedia([]));
  assert.equal(await page.locator('#mediaViewer[open]').count(),0);
  assert.ok(await page.locator('textarea').evaluate(el => el===document.activeElement));
  assert.deepEqual(await page.evaluate(() => window.viewerEvents),[true,false,true,false]);
  assert.equal(await page.locator('#viewerImage').getAttribute('src'),null);
});
test('phone dark feed and original viewer stay usable without outbound requests or pixel persistence', async () => {
  await page.setViewportSize({width:390,height:844});
  await page.locator('[data-view="mob"]').click(); await page.locator('button[data-feed="dark"]').click();
  await page.locator('#imgIn').setInputFiles(await fixture('phone.png',300,1500));
  await page.waitForFunction(() => document.querySelectorAll('#cardMob [data-media-index]').length===1);
  await page.locator('#cardMob [data-media-index="0"]').click();
  const box = await page.locator('#mediaViewer').boundingBox(); assert.ok(box.width<=390 && box.height<=844);
  assert.equal(await page.locator('#mediaViewer').getAttribute('data-feed'),'dark');
  assert.equal(await page.locator('#viewerImage').evaluate(el=>el.naturalHeight),1500);
  const fitted=await page.locator('#viewerImage').boundingBox(); assert.ok(fitted.height<box.height*.65,'fit shows entire tall original within the phone viewport');
  if(process.env.INKOGNITO_SCREENSHOTS) await page.locator('#mediaViewer').screenshot({path:path.join(process.env.INKOGNITO_SCREENSHOTS,'inkognito-original-phone-dark.png')});
  await page.keyboard.press('Tab'); assert.ok(await page.locator('#mediaViewer').evaluate(el=>el.contains(document.activeElement)));
  await page.keyboard.press('Escape');
  await page.locator('[data-pop="p-drafts"]').click();
  const downloadPromise=page.waitForEvent('download'); await page.locator('#dExport').click(); const download=await downloadPromise;
  const exported=fs.readFileSync(await download.path(),'utf8'); assert.ok(!/data:image|blob:/.test(exported));
  assert.ok(!/data:image|blob:/.test(await page.evaluate(()=>JSON.stringify({...localStorage}))));
  assert.deepEqual(requests,[]); assert.deepEqual(errors,[]);
});

async function controlFixtures() {
  await page.setViewportSize({width:1440,height:1100});
  await page.locator('[data-view="desk"]').click();
  const src='data:image/png;base64,'+(await fixture('control.png',60,40)).buffer.toString('base64');
  await page.evaluate(src=>window.mediaTest.setPreviewMedia([{id:'one',src,alt:'First',width:60,height:40},{id:'two',src,alt:'Second',width:60,height:40}]),src);
}
test('editing a description then clicking Remove performs the pending removal', async()=>{
  await controlFixtures();
  await page.getByRole('textbox',{name:'Image 1 description',exact:true}).fill('Edited first');
  await page.getByRole('button',{name:'Remove image 1',exact:true}).click();
  assert.equal(await page.locator('#cardDesk [data-media-index]').count(),1);
  assert.equal(await page.locator('#cardDesk [data-media-index] img').getAttribute('alt'),'Second');
});
test('editing a description then reordering commits both actions',async()=>{
  await controlFixtures();
  await page.getByRole('textbox',{name:'Image 1 description',exact:true}).fill('Edited first');
  await page.getByRole('button',{name:'Move image 1 later',exact:true}).click();
  assert.equal(await page.locator('#cardDesk [data-media-index] img').first().getAttribute('alt'),'Second');
  assert.equal(await page.locator('#cardDesk [data-media-index] img').last().getAttribute('alt'),'Edited first');
});
test('Tab after editing an image description advances to the next enabled control',async()=>{
  await controlFixtures();
  await page.getByRole('textbox',{name:'Image 1 description',exact:true}).fill('Edited first');
  await page.keyboard.press('Tab');
  assert.equal(await page.getByRole('button',{name:'Move image 1 later',exact:true}).evaluate(el=>el===document.activeElement),true);
});
test('picker schedules one native decode at a time and stops at the remaining gallery pixel budget',async()=>{
  await controlFixtures();
  await page.evaluate(()=>{
    const src=document.querySelector('#cardDesk img').src;
    window.mediaTest.setPreviewMedia([{id:'existing',src,alt:'Existing',width:6000,height:6000}]);
    const NativeImage=window.Image,nativeRevoke=URL.revokeObjectURL;
    window.decodeProbe={started:[],pending:[],revoked:[],restore(){window.Image=NativeImage;URL.revokeObjectURL=nativeRevoke;this.pending.splice(0).forEach(release=>release());}};
    URL.revokeObjectURL=function(url){window.decodeProbe.revoked.push(url);return nativeRevoke.call(URL,url);};
    window.Image=function(){const image=new NativeImage();Object.defineProperties(image,{naturalWidth:{value:6000},naturalHeight:{value:6000},src:{set(url){window.decodeProbe.started.push(url);window.decodeProbe.pending.push(()=>{if(image.onload)image.onload();});}}});return image;};
  });
  try{
    const file=await fixture('budget.png',60,40);
    await page.locator('#imgIn').setInputFiles(Array.from({length:8},(_,i)=>({...file,name:'budget-'+i+'.png'})));
    assert.equal(await page.evaluate(()=>window.decodeProbe.started.length),1,'the next decoder cannot start while the first remains pending');
    await page.evaluate(()=>window.decodeProbe.pending.shift()());
    await page.waitForFunction(()=>window.decodeProbe.started.length===2);
    await page.evaluate(()=>window.decodeProbe.pending.shift()());
    await page.waitForFunction(()=>document.querySelector('#mediaNotice').textContent.includes('80 million'));
    assert.equal(await page.evaluate(()=>window.decodeProbe.started.length),2,'over-budget second result prevents remaining six decodes');
    assert.equal(await page.locator('#cardDesk [data-media-index]').getAttribute('data-media-id'),'existing');
    assert.deepEqual(await page.evaluate(()=>window.decodeProbe.revoked.slice().sort()),await page.evaluate(()=>window.decodeProbe.started.slice().sort()));
  }finally{await page.evaluate(()=>window.decodeProbe.restore());}
});

async function controlledSmallDecoder(){
  await page.evaluate(()=>{
    const NativeImage=window.Image,nativeRevoke=URL.revokeObjectURL;
    window.decodeProbe={started:[],pending:[],revoked:[],restore(){window.Image=NativeImage;URL.revokeObjectURL=nativeRevoke;this.pending.splice(0).forEach(release=>release());}};
    URL.revokeObjectURL=function(url){window.decodeProbe.revoked.push(url);return nativeRevoke.call(URL,url);};
    window.Image=function(){const image=new NativeImage();Object.defineProperties(image,{naturalWidth:{value:60},naturalHeight:{value:40},src:{set(url){window.decodeProbe.started.push(url);window.decodeProbe.pending.push((ok=true)=>{if(ok){if(image.onload)image.onload();}else if(image.onerror)image.onerror();});}}});return image;};
  });
}
test('cancelled picker stops remaining decodes and revokes every staged URL',async()=>{
  await controlFixtures(); await controlledSmallDecoder();
  try{
    const file=await fixture('cancel.png',60,40);
    await page.locator('#imgIn').setInputFiles(Array.from({length:3},(_,i)=>({...file,name:'cancel-'+i+'.png'})));
    await page.evaluate(()=>window.decodeProbe.pending.shift()());
    await page.waitForFunction(()=>window.decodeProbe.started.length===2);
    await page.evaluate(()=>{window.mediaTest.setPreviewMedia([]);window.decodeProbe.pending.shift()();});
    await page.waitForFunction(()=>window.decodeProbe.revoked.length===2);
    assert.equal(await page.evaluate(()=>window.decodeProbe.started.length),2);
    assert.equal(await page.locator('#cardDesk [data-media-index]').count(),0);
    assert.deepEqual(await page.evaluate(()=>window.decodeProbe.revoked.slice().sort()),await page.evaluate(()=>window.decodeProbe.started.slice().sort()));
  }finally{await page.evaluate(()=>window.decodeProbe.restore());}
});
test('failed later decode revokes staged URLs and retains the existing gallery',async()=>{
  await controlFixtures(); await controlledSmallDecoder();
  try{
    const file=await fixture('failure.png',60,40);
    await page.locator('#imgIn').setInputFiles(Array.from({length:3},(_,i)=>({...file,name:'failure-'+i+'.png'})));
    await page.evaluate(()=>window.decodeProbe.pending.shift()());
    await page.waitForFunction(()=>window.decodeProbe.started.length===2);
    await page.evaluate(()=>window.decodeProbe.pending.shift()(false));
    await page.waitForFunction(()=>document.querySelector('#mediaNotice').textContent.includes('could not be decoded'));
    assert.equal(await page.evaluate(()=>window.decodeProbe.started.length),2);
    assert.equal(await page.locator('#cardDesk [data-media-index]').count(),2);
    assert.equal(await page.locator('#cardDesk [data-media-index]').first().getAttribute('data-media-id'),'one');
    assert.deepEqual(await page.evaluate(()=>window.decodeProbe.revoked.slice().sort()),await page.evaluate(()=>window.decodeProbe.started.slice().sort()));
  }finally{await page.evaluate(()=>window.decodeProbe.restore());}
});

async function externalFixture() {
  await page.keyboard.press('Escape');
  await page.setViewportSize({width:1440,height:1100});
  const src='data:image/png;base64,'+(await fixture('library.png',80,60)).buffer.toString('base64');
  await page.evaluate(src=>{
    window.navigationEvents=[];
    if(!window.navigationListener){window.navigationListener=e=>window.navigationEvents.push(e.detail);document.addEventListener('inkognito:viewer-navigate',window.navigationListener);}
    window.mediaTest.setPreviewMedia([{id:'library-one',src,alt:'Library one',width:80,height:60}]);
  },src);
  assert.equal(await page.evaluate(()=>typeof window.mediaTest.setMediaViewerNavigation),'function');
}
test('external count, deliberate navigation and boundaries use host position without local movement',async()=>{
  await externalFixture();
  assert.equal(await page.evaluate(()=>window.mediaTest.setMediaViewerNavigation({position:50,total:102})),true);
  await page.evaluate(()=>window.mediaTest.openMediaViewer(0));
  assert.equal(await page.locator('#viewerCount').textContent(),'51 / 102');
  if(process.env.INKOGNITO_SCREENSHOTS)await page.locator('#mediaViewer').screenshot({path:path.join(process.env.INKOGNITO_SCREENSHOTS,'inkognito-external-viewer.png')});
  await page.locator('#viewerNext').click();await page.keyboard.press('ArrowLeft');
  assert.deepEqual(await page.evaluate(()=>window.navigationEvents),[{direction:1},{direction:-1}]);
  assert.equal(await page.locator('#viewerDescription').textContent(),'Library one');
  await page.evaluate(()=>window.mediaTest.setMediaViewerNavigation({position:0,total:102}));
  assert.equal(await page.locator('#viewerPrev').isDisabled(),true);
  await page.keyboard.press('ArrowLeft');
  await page.evaluate(()=>window.mediaTest.setMediaViewerNavigation({position:101,total:102}));
  assert.equal(await page.locator('#viewerNext').isDisabled(),true);
  await page.keyboard.press('ArrowRight');
  assert.equal(await page.evaluate(()=>window.navigationEvents.length),2);
});
test('navigation validation preserves mode and setter preserves zoom, editor and storage',async()=>{
  await externalFixture();
  await page.evaluate(()=>window.mediaTest.setMediaViewerNavigation({position:5,total:30}));
  await page.evaluate(()=>window.mediaTest.openMediaViewer(0));
  await page.locator('#viewerZoom').click();
  await page.evaluate(()=>document.querySelector('#ta').setSelectionRange(1,4));
  const before=await page.evaluate(()=>({text:document.querySelector('#ta').value,selection:[document.querySelector('#ta').selectionStart,document.querySelector('#ta').selectionEnd],storage:JSON.stringify(localStorage)}));
  for(const value of [undefined,{},[],{position:0,total:0},{position:-1,total:10},{position:10,total:10},{position:0.5,total:10},{position:0,total:'10'},{position:0,total:Infinity},{position:0,total:9007199254740992},{position:1,total:10,extra:true}]){
    assert.equal(await page.evaluate(value=>window.mediaTest.setMediaViewerNavigation(value),value),false);
    assert.equal(await page.locator('#viewerCount').textContent(),'6 / 30');
  }
  assert.equal(await page.evaluate(()=>window.mediaTest.setMediaViewerNavigation({position:6,total:30})),true);
  assert.equal(await page.locator('#viewerZoom').getAttribute('aria-pressed'),'true');
  assert.deepEqual(await page.evaluate(()=>({text:document.querySelector('#ta').value,selection:[document.querySelector('#ta').selectionStart,document.querySelector('#ta').selectionEnd],storage:JSON.stringify(localStorage)})),before);
  assert.deepEqual(await page.evaluate(()=>window.navigationEvents),[]);
});
test('external media replacement stays open, resets fit and null restores local navigation',async()=>{
  await externalFixture();
  await page.evaluate(()=>{window.mediaTest.setMediaViewerNavigation({position:0,total:50});window.mediaTest.openMediaViewer(0)});
  await page.locator('#viewerZoom').click();
  await page.evaluate(()=>{const src=document.querySelector('#viewerImage').src;window.mediaTest.setPreviewMedia([{id:'library-two',src,alt:'Library two',width:80,height:60}]);window.mediaTest.setMediaViewerNavigation({position:1,total:50})});
  assert.equal(await page.locator('#mediaViewer[open]').count(),1);
  assert.equal(await page.locator('#viewerDescription').textContent(),'Library two');
  assert.equal(await page.locator('#viewerZoom').getAttribute('aria-pressed'),'false');
  assert.equal(await page.locator('#viewerCount').textContent(),'2 / 50');
  await page.evaluate(()=>window.mediaTest.setMediaViewerNavigation(null));
  assert.equal(await page.locator('#viewerCount').textContent(),'1 / 1');
  assert.equal(await page.locator('#viewerNext').isDisabled(),true);
});
test('closing, clearing and changing drafts reset external mode while local gallery stays capped at 20',async()=>{
  await externalFixture();
  for(const reset of ['close','clear','draft']){
    await page.evaluate(()=>{window.mediaTest.setMediaViewerNavigation({position:3,total:40});window.mediaTest.openMediaViewer(0)});
    if(reset==='close')await page.keyboard.press('Escape');
    if(reset==='clear')await page.evaluate(()=>window.mediaTest.setPreviewMedia([]));
    if(reset==='draft'){await page.keyboard.press('Escape');await page.evaluate(()=>window.mediaTest.setMediaViewerNavigation({position:3,total:40}));await page.locator('[data-pop="p-drafts"]').click();await page.locator('#dNew').click();}
    const src='data:image/png;base64,'+(await fixture('local.png',80,60)).buffer.toString('base64');
    await page.evaluate(src=>{window.mediaTest.setPreviewMedia([{id:'local',src,alt:'Local',width:80,height:60}]);window.mediaTest.openMediaViewer(0)},src);
    assert.equal(await page.locator('#viewerCount').textContent(),'1 / 1');await page.keyboard.press('Escape');
  }
  const src='data:image/png;base64,'+(await fixture('twenty.png',80,60)).buffer.toString('base64');
  assert.equal(await page.evaluate(src=>window.mediaTest.setPreviewMedia(Array.from({length:20},(_,i)=>({id:String(i),src,alt:String(i),width:80,height:60}))),src),true);
  await page.evaluate(()=>window.mediaTest.openMediaViewer(0));await page.keyboard.press('ArrowRight');
  assert.equal(await page.locator('#viewerCount').textContent(),'2 / 20');
  assert.equal(await page.evaluate(src=>window.mediaTest.setPreviewMedia(Array.from({length:21},(_,i)=>({id:String(i),src,alt:'',width:80,height:60}))),src),false);
  assert.equal(await page.locator('#viewerCount').textContent(),'2 / 20');await page.keyboard.press('Escape');
  assert.deepEqual(requests,[]);assert.deepEqual(errors,[]);
  assert.ok(!/data:image|blob:/.test(await page.evaluate(()=>JSON.stringify({...localStorage}))));
});
