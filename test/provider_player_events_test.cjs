const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../android/app/src/main/assets/provider_player.js'), 'utf8');
function player() {
  let now = 0;
  const events = {}, messages = [], timers = [];
  const media = {paused:false, ended:false, currentTime:1, readyState:0,
    matches: tag => tag === 'video', closest: () => null, pause() { this.paused = true; }};
  const document = {hidden:false, documentElement:null,
    getElementById: id => id === 'video' ? media : null,
    querySelector: () => media, querySelectorAll: () => [],
    addEventListener: (name, fn) => {events[name] = fn;}};
  const window = {addEventListener: (name, fn) => {events[name] = fn;}};
  vm.runInNewContext(script, {window, document, frames:[],
    console:{info: value => messages.push(value)}, Date:{now:() => now},
    MutationObserver:class { observe() {} },
    setInterval:(fn, period) => {timers.push({fn,period}); return timers.length;}, clearInterval:() => {}});
  return {media, document, messages, events,
    tick(seconds) {now = seconds * 1000; timers.find(t => t.period === 5000).fn();},
    play() {media.paused = false; events.playing({target:media});},
    errors:() => messages.filter(m => m === '__PROVIDER_PLAYER_ERROR__').length};
}

test('provider video stall reports once after 20 seconds without progress', () => {
  const p = player(); p.play(); p.tick(0); p.tick(19);
  assert.equal(p.errors(),0);
  p.media.currentTime = 2; p.tick(20); p.tick(39);
  assert.equal(p.errors(),0);
  p.tick(40); p.tick(60);
  assert.equal(p.errors(),1);
});
test('pauses, backgrounding and ended media never trigger a server switch', () => {
  for (const state of ['paused','ended','hidden','background']) {
    const p = player(); p.play(); p.tick(0);
    if (state === 'hidden') p.document.hidden = true;
    else if (state === 'background') p.events.message({data:{providerPlayerPause:true}});
    else p.media[state] = true;
    p.tick(90);
    assert.equal(p.errors(),0,state);
  }
});
test('media errors trigger fallback but resource and ad errors do not', () => {
  const p = player();
  p.events.error({target:{}});
  p.events.error({target:{matches:() => true, closest:() => ({})}});
  assert.equal(p.errors(),0);
  p.events.error({target:p.media});
  p.events.error({target:p.media});
  assert.equal(p.errors(),1);
});
test('health monitoring resumes after returning from background', () => {
  const p = player(); p.play(); p.tick(0);
  p.events.message({data:{providerPlayerPause:true}}); p.tick(90);
  p.play(); p.tick(95); p.tick(115);
  assert.equal(p.errors(),1);
});
