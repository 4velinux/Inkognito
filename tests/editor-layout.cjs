/* Development-only interaction and layout checks for the shared single-file editor. */
const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const {chromium}=require(process.env.INKOGNITO_PLAYWRIGHT||'playwright-core');
let browser;
before(async()=>{browser=await chromium.launch({executablePath:process.env.INKOGNITO_CHROMIUM});});
after(async()=>{if(browser)await browser.close();});
async function open(width,height=900){const page=await browser.newPage({viewport:{width,height}});await page.goto('file://'+path.resolve(__dirname,'../inkognito.html'));return page;}
function luminance(rgb){const c=rgb.match(/[\d.]+/g).slice(0,3).map(Number).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;});return c[0]*.2126+c[1]*.7152+c[2]*.0722;}
for(const width of [1440,820,390])test(`editor controls stay clear and contained at ${width}px`,async()=>{
  const page=await open(width);
  try{
    const colors=await page.locator('.ed').evaluate(el=>({border:getComputedStyle(el).borderTopColor,background:getComputedStyle(el).backgroundColor}));
    const values=[luminance(colors.border),luminance(colors.background)].sort((a,b)=>b-a);
    assert.ok((values[0]+.05)/(values[1]+.05)>=3,'the editor boundary remains distinguishable from its surface');
    assert.equal(await page.locator('label[for="ta"]').count(),1,'the editable text has a visible label');
    assert.equal(await page.locator('#ta').evaluate(el=>getComputedStyle(el).padding),await page.locator('#backdrop').evaluate(el=>getComputedStyle(el).padding),'editor highlights retain the same text inset');
    await page.locator('#ta').focus();
    assert.notEqual(await page.locator('.ed').evaluate(el=>getComputedStyle(el).borderTopColor),colors.border,'focus visibly changes the editor boundary');
    await page.locator('#ta').fill('Synthetic editorial text.\n\n'+('Long readable paragraph for scrolling. '.repeat(100)));
    await page.locator('#ta').evaluate(el=>{el.scrollTop=200;el.dispatchEvent(new Event('scroll'));});
    assert.equal(await page.locator('#backdrop').evaluate(el=>el.scrollTop),await page.locator('#ta').evaluate(el=>el.scrollTop));
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'the page does not scroll sideways');
    await page.locator('[data-view="both"]').click();
    await page.locator('#stage').focus();
    assert.equal(await page.locator('#stage').evaluate(el=>el===document.activeElement),true,'the fixed-size previews can be scrolled by keyboard');
    const start=await page.locator('#stage').evaluate(el=>el.scrollLeft);await page.keyboard.press('ArrowRight');
    await page.waitForFunction(start=>document.querySelector('#stage').scrollLeft>start,start);
    await page.evaluate(()=>scrollTo(0,0));
    if(process.env.INKOGNITO_SCREENSHOTS)await page.screenshot({path:path.join(process.env.INKOGNITO_SCREENSHOTS,`inkognito-editor-${width}.png`),fullPage:true});
  }finally{await page.close();}
});
test('font menu stays inside a short phone viewport and scrolls internally',async()=>{
  const page=await open(390,650);
  try{
    await page.locator('[data-pop="p-fonts"]').click();
    const box=await page.locator('#p-fonts').boundingBox();
    assert.ok(box.y>=8&&box.y+box.height<=642,'formatting options remain within the visible viewport');
    assert.ok(await page.locator('#p-fonts').evaluate(el=>el.scrollHeight>el.clientHeight),'long formatting menus have internal scrolling');
    if(process.env.INKOGNITO_SCREENSHOTS)await page.screenshot({path:path.join(process.env.INKOGNITO_SCREENSHOTS,'inkognito-editor-phone-menu.png')});
  }finally{await page.close();}
});
test('native textarea resizing stays usable within the screen and preserves text',async()=>{
  const page=await open(1440,900);
  try{
    const text='Resize this synthetic text without changing it.';await page.locator('#ta').fill(text);
    const box=await page.locator('#ta').boundingBox();
    await page.mouse.move(box.x+box.width-4,box.y+box.height-4);await page.mouse.down();await page.mouse.move(box.x+box.width-4,box.y+box.height+800,{steps:5});await page.mouse.up();
    const resized=await page.locator('#ta').boundingBox();
    assert.ok(resized.height>box.height,'the native resize grip changes the editing height');
    assert.ok(resized.height<=720,'resizing keeps the text area bounded with internal scrolling');
    assert.equal(await page.locator('#ta').inputValue(),text);
  }finally{await page.close();}
});
test('an open formatting menu follows a window resize',async()=>{
  const page=await open(1440,1000);
  try{
    await page.locator('[data-pop="p-fonts"]').click();await page.setViewportSize({width:390,height:650});
    await page.waitForFunction(()=>{const r=document.querySelector('#p-fonts').getBoundingClientRect();return r.left>=8&&r.right<=382&&r.top>=8&&r.bottom<=642;},null,{timeout:1000});
    const box=await page.locator('#p-fonts').boundingBox();
    assert.ok(box.x>=8&&box.x+box.width<=382&&box.y>=8&&box.y+box.height<=642,'resizing does not strand the open menu outside the screen');
  }finally{await page.close();}
});
test('dark editor fields keep visible boundaries and focus without changing feed chrome',async()=>{
  const page=await open(820);
  try{
    const card=await page.locator('#cardDesk').evaluate(el=>({width:el.clientWidth,background:getComputedStyle(el).backgroundColor}));
    await page.locator('#themeBtn').click();await page.locator('#themeBtn').click();
    const colors=await page.locator('.ed').evaluate(el=>({border:getComputedStyle(el).borderTopColor,background:getComputedStyle(el).backgroundColor}));
    const values=[luminance(colors.border),luminance(colors.background)].sort((a,b)=>b-a);
    assert.ok((values[0]+.05)/(values[1]+.05)>=3);await page.locator('#ta').focus();
    assert.notEqual(await page.locator('.ed').evaluate(el=>getComputedStyle(el).borderTopColor),colors.border);
    assert.deepEqual(await page.locator('#cardDesk').evaluate(el=>({width:el.clientWidth,background:getComputedStyle(el).backgroundColor})),card);
    await page.evaluate(()=>scrollTo(0,0));
    if(process.env.INKOGNITO_SCREENSHOTS)await page.screenshot({path:path.join(process.env.INKOGNITO_SCREENSHOTS,'inkognito-editor-dark-820.png'),fullPage:true});
  }finally{await page.close();}
});
