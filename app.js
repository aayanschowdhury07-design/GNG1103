// ---------- shared sample state ----------
const state = {
  booking:{service:'Physiotherapy · follow-up',clin:'Dr. Kwame Osei',time:'9:00 am',dur:'30 min',who:'me'},
  family:[{id:'f1',name:'Arjun Raman',rel:'Child',dob:'2017-04-12'}], famFrom:'profile',
  history:[
    {date:'Sep 15, 2026',svc:'Physiotherapy · follow-up',clin:'Dr. Kwame Osei',clinic:'Maple Grove Clinic',fee:95,owing:0,who:'Priya Raman'},
    {date:'Sep 1, 2026',svc:'Physiotherapy · initial assessment',clin:'Dr. Kwame Osei',clinic:'Maple Grove Clinic',fee:130,owing:40,who:'Priya Raman'},
    {date:'Aug 20, 2026',svc:'Chiropractic · adjustment',clin:'Dr. Rania Daoud',clinic:'Maple Grove Clinic',fee:70,owing:0,who:'Arjun Raman'},
    {date:'Jun 11, 2026',svc:'Physiotherapy · follow-up',clin:'Sam Whitlock, PT',clinic:'Lakeshore Physio',fee:90,owing:0,who:'Priya Raman'},
  ],
  appt:{status:'confirmed',time:'9:00 am',date:'Tue Sep 29',service:'Physiotherapy · follow-up',clin:'Dr. Kwame Osei',intake:false,onWaitlist:false},
  queue:[
    {id:1,name:'Priya Raman',ini:'PR',clin:'osei',time:'9:00',svc:'Physio follow-up',status:'confirmed',forms:false,ticket:'A-15'},
    {id:2,name:'Marcus Chen',ini:'MC',clin:'osei',time:'9:30',svc:'Physio follow-up',status:'late',forms:true,ticket:'A-16'},
    {id:3,name:'An Nguyen',ini:'AN',clin:'lam',time:'9:00',svc:'Initial assessment',status:'invisit',forms:true,ticket:'A-14',since:8},
    {id:4,name:'Walk-in #12',ini:'W',clin:'walk',time:'9:05',svc:'Walk-in',status:'waiting',forms:true,ticket:'A-13',since:14},
    {id:5,name:'Lucie Fortin',ini:'LF',clin:'osei',time:'10:00',svc:'Physio follow-up',status:'booked',forms:true,ticket:'A-17'},
    {id:6,name:'Raj Singh',ini:'RS',clin:'lam',time:'10:00',svc:'Physio follow-up',status:'unconfirmed',forms:false,ticket:'A-18'},
  ],
  pNotifs:[
    {t:'Reminder: Physio tomorrow 9:00 am with Dr. Osei. Tap to confirm.',s:'Yesterday 9:00 am · push',k:'info'},
    {t:'Please complete your reason-for-visit form before Tuesday.',s:'Yesterday 9:01 am · SMS',k:'warn'},
    {t:'Booked: Physio, Tue Sep 29, 9:00 am. Manage your visit any time from this link.',s:'Sep 22 · SMS + email',k:'good'},
    {t:'Clinic notice: Parking lot B closed Sep 28 – Oct 2.',s:'Sep 26 · push',k:'mute'},
  ],
  sAlerts:[
    {t:'Lucie Fortin cancelled 10:30 with Dr. Osei. Slot offered to waitlist (1 of 3).',s:'9:28 am',k:'warn'},
    {t:'Marcus Chen is 12 min late and not checked in.',s:'9:27 am',k:'crit'},
    {t:'Intake nudges sent to 5 patients; 2 fell back to SMS.',s:'8:30 am',k:'info'},
    {t:'Dana updated the cancellation window to 24 h.',s:'Yesterday',k:'mute'},
  ],
  filter:'all', selectedPatient:1, freedOffered:true,
  missedFilter:'open',
  missed:[
    {id:1,date:'Sep 28',time:'2:40 pm',name:'Tomás Rivera',clin:'Dr. Osei',svc:'Physio follow-up',reminder:'Delivered, no reply',prior:2,status:'open'},
    {id:2,date:'Sep 25',time:'9:00 am',name:'Grace Liu',clin:'M. Lam',svc:'Initial assessment',reminder:'Confirmed by SMS',prior:0,status:'open'},
    {id:3,date:'Sep 22',time:'11:30 am',name:'Omar Haddad',clin:'Dr. Osei',svc:'Physio follow-up',reminder:'SMS failed, email sent',prior:0,status:'rebooked'},
    {id:4,date:'Sep 17',time:'4:00 pm',name:'Elena Petrova',clin:'Dr. Daoud',svc:'Chiro adjustment',reminder:'Delivered, no reply',prior:1,status:'excused'},
    {id:5,date:'Sep 9',time:'10:00 am',name:'Ben Carter',clin:'M. Lam',svc:'Physio follow-up',reminder:'Confirmed by push',prior:0,status:'contacted'},
  ],
  blockTypes:[{name:'Break',scope:'Each clinician'},{name:'Not in',scope:'Each clinician'},{name:'Admin time',scope:'Each clinician'},{name:'Statutory holiday',scope:'Whole clinic'}],
  tplPick:'reminder24',
  tpls:{
    reminder24:{label:'Reminder, 24 h before',text:'Hi {first_name}, reminder: {service} with {clinician} tomorrow at {time}, Maple Grove Clinic. Tap to confirm: {link}. Need to change it? Same link. Reply STOP to opt out.'},
    cancelPatient:{label:'Cancellation, patient cancelled',text:'Hi {first_name}, your {service} on {date} at {time} is cancelled. Book again any time: {link}. Reply STOP to opt out.'},
    cancelClinic:{label:'Cancellation, clinic cancelled',text:"Hi {first_name}, we're sorry: we had to cancel your {service} with {clinician} on {date} at {time} ({reason}). You're first in line for a new time: {link}"},
    missed:{label:'Missed visit follow-up',text:'Hi {first_name}, we missed you at {time} today. No problem, life happens. Pick a new time that suits you: {link}. Reply STOP to opt out.'},
  }
};
const CAL_BASE='2026-09-29';
const STATUS={booked:['mute','Booked'],unconfirmed:['warn','Unconfirmed'],confirmed:['info','Confirmed'],checked:['good','Checked in'],waiting:['warn','Waiting'],invisit:['info','In visit'],done:['good','Complete'],late:['crit','Late'],noshow:['crit','No-show'],cancelled:['mute','Cancelled']};

// ---------- helpers ----------
const $=(s,r=document)=>r.querySelector(s), $$=(s,r=document)=>[...r.querySelectorAll(s)];
function toast(which,msg){const el=$('#'+which+'-toast');el.textContent=msg;el.classList.add('show');clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),2200)}
const hints={patient:'Tap through the patient app: book as a guest with a phone code, fill intake, check in, and watch your place in the queue. Actions in the staff app change what the patient sees.',staff:'The staff app is built around the live queue: arrive, call next, mark late or no-show, and answer waitlist offers with one tap. Try "Call next" then switch back to the patient app.',web:'The admin website is where the clinic is set up and run: calendar, rules, roles, audit log and reports. Use the left navigation.'};
function surface(id,btn){$$('.stage').forEach(s=>s.classList.toggle('active',s.id==='stage-'+id));$$('.switch button').forEach(b=>b.setAttribute('aria-selected',b===btn));$('#hint').textContent=hints[id];cur.surface=id;syncHash();renderAll()}
// screens that belong under a tab-bar item, so the tab stays highlighted
const TAB_OF={book2:'book',book3:'book',otp:'book',family:'profile',history:'profile'};
function showScreen(root,id){$$('.screen',root).forEach(s=>s.classList.toggle('active',s.dataset.s===id));const tabs=$$('.tabbar button',root.parentElement);tabs.forEach(b=>b.setAttribute('aria-selected',b.dataset.tab===(TAB_OF[id]||id)));$('.screen.active',root).scrollTop=0}
function pgo(id){showScreen($('#p-screens'),id);cur.patient=id;syncHash();renderPatient()}
function sgo(id){showScreen($('#s-screens'),id);cur.staff=id;syncHash();renderStaff()}
function wgo(id,btn){$$('.page').forEach(p=>p.classList.toggle('active',p.dataset.p===id));const btns=$$('.side button');btns.forEach(b=>b.setAttribute('aria-selected',btn?b===btn:b.getAttribute('onclick').includes("'"+id+"'")));cur.web=id;syncHash();renderWeb()}

// ---------- deep links: #patient/book2, #staff/waitlist, #web/cal ----------
// Every screen has its own address so a link or a reload lands on it. One-time screens
// (a confirmation, an offer, a code entry) fall back to a stable screen, the way Jane
// never restores #wait_list.
// The calendar day is part of the address too (#web/cal/2026-09-30), as in Cliniko.
const cur={surface:'patient',patient:'home',staff:'queue',web:'dash',calDate:CAL_BASE};
const REOPEN_AS={confirmed:'home',offer:'home',otp:'book3'};
function syncHash(){const h='#'+cur.surface+'/'+cur[cur.surface]+(cur.surface==='web'&&cur.web==='cal'?'/'+cur.calDate:'');if(location.hash!==h)history.replaceState(null,'',h)}
function openFromHash(){
  const [s,id,day]=location.hash.slice(1).split('/'),i=['patient','staff','web'].indexOf(s);
  if(s==='web'&&id==='cal'&&/^\d{4}-\d{2}-\d{2}$/.test(day||''))cur.calDate=day;
  if(i<0)return syncHash();
  surface(s,$$('.switch button')[i]);
  if(s==='patient'){const t=REOPEN_AS[id]||id;if($(`#p-screens [data-s="${t}"]`))pgo(t)}
  else if(s==='staff'&&$(`#s-screens [data-s="${id}"]`))sgo(id);
  else if(s==='web'&&$(`.page[data-p="${id}"]`))wgo(id);
}
window.addEventListener('hashchange',openFromHash);
function pill(st){const [k,l]=STATUS[st];return `<span class="pill ${k}"><i class="dot"></i>${l}</span>`}
function me(){return state.queue.find(q=>q.id===1)}
function initials(n){return n.replace('Dr. ','').replace(',','').split(' ').map(w=>w[0]).slice(0,2).join('')}
function whoName(){const f=state.family.find(f=>f.id===state.booking.who);return f?f.name:'Priya Raman'}
function forLabel(name){return name&&name!=='Priya Raman'?' · for '+name.split(' ')[0]:''}
function niceDate(iso){return iso?new Date(iso+'T00:00').toLocaleDateString('en-CA',{month:'short',day:'numeric',year:'numeric'}):'date of birth not set'}

// ---------- patient ----------
const services=[['Physiotherapy · follow-up','30 min · returning patients'],['Physiotherapy · initial assessment','45 min · new concern'],['Chiropractic · adjustment','20 min · Thursdays']];
const clins=[['Dr. Kwame Osei','Physiotherapist · next: today 2:40 pm'],['Mei Lam, PT','Physiotherapist · next: Wed 9:00 am'],['First available','Any clinician']];
const slots=[['9:00',true],['9:30',false],['10:00',false],['10:30',false,'freed'],['11:00',false],['2:40',false],['3:10',false],['4:00',false],['4:30',false]];
function renderPatient(){
  const a=state.appt, q=me();
  $('#p-todo-count').textContent=a.intake?'0 left':'1 left';
  $('#p-todo-count').className=`pill ${a.intake?'good':'warn'}`;
  $('#p-reason-todo').innerHTML=a.intake
    ?'<span class="pill good">Done</span><div class="grow"><div class="t">Reason for visit</div><div class="s">Submitted just now</div></div>'
    :'<span class="pill warn">Open</span><div class="grow"><div class="t">Reason for visit</div><div class="s">2 min · needed by Tue 8:30 am</div></div><button class="btn sm" onclick="pgo(\'intake\')">Fill</button>';
  // hero
  const h=$('#p-hero');
  if(a.status==='cancelled'){h.innerHTML=`<p class="eyebrow">No upcoming visit</p><h3>Book when you're ready</h3><button class="btn" onclick="pgo('book')">Book a visit</button>`}
  else if(q.status==='checked'||q.status==='waiting'){h.innerHTML=`<p class="eyebrow">You're checked in</p><h3>${q.status==='waiting'?'2 people ahead of you':'You are next'}</h3><p style="margin:0 0 10px;opacity:.9">Estimated wait about ${q.status==='waiting'?'11':'4'} minutes. We'll buzz you.</p><button class="btn" onclick="pgo('checkin')">See queue</button>`}
  else if(q.status==='invisit'){h.innerHTML=`<p class="eyebrow">Now</p><h3>Dr. Osei is ready for you</h3><p style="margin:0;opacity:.9">Room 2, down the hall on the left.</p>`}
  else if(q.status==='done'){h.innerHTML=`<p class="eyebrow">Visit complete</p><h3>Thanks, Priya</h3><p style="margin:0 0 10px;opacity:.9">Book your next follow-up while it's fresh.</p><button class="btn" onclick="pgo('book')">Book follow-up</button>`}
  else{h.innerHTML=`<p class="eyebrow">Next visit · ${a.date}</p><h3>${a.time} · ${a.service}</h3><p style="margin:0 0 10px;opacity:.9">${a.clin} · Maple Grove Clinic${forLabel(a.for)}${a.onWaitlist?' · on waitlist for earlier':''}</p><div class="row"><button class="btn" onclick="pgo('appt')">Manage</button><button class="btn" onclick="pgo('checkin')">Check in</button></div>`}
  // book
  $('#p-who').innerHTML=[['me','Me'],...state.family.map(f=>[f.id,f.name.split(' ')[0]])].map(([id,l])=>`<button aria-pressed="${state.booking.who===id}" onclick="state.booking.who='${id}';renderPatient()">${l}</button>`).join('')+`<button aria-pressed="false" onclick="state.famFrom='book';pgo('family')">+ Add</button>`;
  $('#p-services').innerHTML=services.map(([n,s])=>`<button class="choice" aria-pressed="${state.booking.service===n}" onclick="state.booking.service='${n}';renderPatient()"><div class="grow"><div class="t" style="font-weight:600">${n}</div><div class="s small muted">${s}</div></div></button>`).join('');
  $('#p-clin').innerHTML=clins.map(([n,s])=>`<button class="choice" aria-pressed="${state.booking.clin===n}" onclick="state.booking.clin='${n}';renderPatient()"><div class="avatar">${initials(n)}</div><div class="grow"><div style="font-weight:600">${n}</div><div class="small muted">${s}</div></div></button>`).join('');
  $('#p-slots').innerHTML=slots.map(([t,,f])=>`<button aria-pressed="${state.booking.time===t+(t.startsWith('9')||t.startsWith('1')?' am':' pm')}" class="${f||''}" onclick="state.booking.time='${t}${t.startsWith('9')||t.startsWith('1')?' am':' pm'}';renderPatient()">${t}</button>`).join('');
  const sum=`<b>${state.booking.service}</b><br>For ${whoName()}<br>${state.booking.clin}<br>Tue Sep 29 · ${state.booking.time}<br>Maple Grove Clinic, 214 Elm Ave`;
  $('#p-summary').innerHTML=sum;$('#p-summary2').innerHTML=sum;
  // appt card
  $('#p-apptcard').innerHTML=`<div class="row between"><p class="eyebrow">${a.date}</p>${pill(a.status==='cancelled'?'cancelled':q.status==='confirmed'?'confirmed':q.status)}</div><h3 style="font-size:20px;margin:4px 0">${a.time} · ${a.service}</h3><p class="small muted" style="margin:0">${a.clin} · Maple Grove Clinic · 214 Elm Ave${forLabel(a.for)}</p><div class="row" style="margin-top:10px"><span class="pill ${a.intake?'good':'warn'}">Forms ${a.intake?'done':'1 open'}</span><span class="pill mute">Ref APT-20931</span></div>`;
  // check-in
  const c=$('#p-checkin');
  if(q.status==='confirmed'||q.status==='booked'){c.innerHTML=`<div class="card stack"><p class="eyebrow">Tue Sep 29 · 9:00 am · Dr. Osei</p><p style="margin:0">You're 140 m from Maple Grove Clinic. Check-in is open.</p>${a.intake?'':'<div class="banner">One form is still open. You can check in now and finish it while you wait.</div>'}<button class="btn primary block" onclick="checkIn()">I'm here</button><p class="small muted" style="margin:0;text-align:center">Or enter code <b class="num">7 3 1 9</b> on the front-desk tablet</p></div>`}
  else if(q.status==='checked'||q.status==='waiting'){const ahead=q.status==='waiting'?2:0;c.innerHTML=`<div class="card" style="text-align:center"><p class="eyebrow">Ticket ${q.ticket}</p><div class="queue-ring" style="--pct:${ahead?40:85}%"><div><b>${ahead}</b><span class="small muted">ahead of you</span></div></div><h3 style="font-size:18px">About ${ahead?11:4} minutes</h3><p class="small muted" style="margin:4px 0 0">Dr. Osei is running 6 min behind. Feel free to step out; we'll send a push when you're next.</p></div><div class="card list" style="padding:0 14px;margin-top:12px"><div class="item"><span class="pill good">Checked in</span><div class="grow"><div class="t">9:${ahead?'41':'52'} am</div><div class="s">Front desk notified</div></div></div>${a.intake?'':'<div class="item"><span class="pill warn">Open</span><div class="grow"><div class="t">Reason for visit</div><div class="s">Finish while you wait</div></div><button class="btn sm" onclick="pgo(\'intake\')">Fill</button></div>'}<div class="item"><span class="pill mute">Now</span><div class="grow"><div class="t">Serving A-14</div><div class="s">Board in the waiting room shows tickets only</div></div></div></div>`}
  else if(q.status==='invisit'){c.innerHTML=`<div class="hero info"><p class="eyebrow">Now</p><h3>Please go to Room 2</h3><p style="margin:0;opacity:.9">Dr. Kwame Osei · down the hall on the left</p></div>`}
  else if(q.status==='done'){c.innerHTML=`<div class="card" style="text-align:center"><div class="avatar" style="width:56px;height:56px;margin:0 auto 8px;background:var(--good-soft);color:var(--good);font-size:24px">✓</div><h3>Visit complete</h3><p class="small muted">Total time in clinic: 34 min. Book your next follow-up from Home.</p></div>`}
  else{c.innerHTML=`<div class="card"><p class="small muted" style="margin:0">Check-in opens 60 minutes before your visit, when you're near the clinic.</p></div>`}
  // family
  $('#p-family').innerHTML=state.family.length?state.family.map(f=>`<div class="item"><div class="avatar">${initials(f.name)}</div><div class="grow"><div class="t">${f.name}</div><div class="s">${f.rel} · born ${niceDate(f.dob)}</div></div><button class="btn sm" onclick="state.booking.who='${f.id}';pgo('book')">Book</button></div>`).join(''):'<div class="item"><div class="grow"><div class="s">No one added yet. Add a child, parent or partner to book for them.</div></div></div>';
  // history and receipts
  const owing=state.history.reduce((t,v)=>t+v.owing,0);
  $('#p-balance').innerHTML=owing?`<div class="row between"><div><p class="eyebrow">Balance owing</p><b style="font-family:var(--display);font-size:22px" class="num">$${owing.toFixed(2)}</b></div><button class="btn sm primary" onclick="payBalance()">Pay now</button></div>`:`<div class="row between"><div><p class="eyebrow">Balance owing</p><b style="font-family:var(--display);font-size:22px" class="num">$0.00</b></div><span class="pill good">All paid</span></div>`;
  $('#p-history').innerHTML=state.history.map((v,i)=>`<div class="item"><span class="pill ${v.owing?'warn':'good'}">${v.owing?'$'+v.owing+' owing':'Paid'}</span><div class="grow"><div class="t">${v.svc}</div><div class="s">${v.date} · ${v.clin} · ${v.clinic}${forLabel(v.who)}</div></div><button class="btn sm" onclick="toast('p','Receipt for ${v.date} emailed')">Receipt</button></div>`).join('');
  // notifs
  $('#p-notifs').innerHTML=state.pNotifs.map(n=>`<div class="item"><span class="pill ${n.k}" style="width:8px;height:8px;padding:0;border-radius:50%"></span><div class="grow"><div class="t" style="font-weight:500">${n.t}</div><div class="s">${n.s}</div></div></div>`).join('');
}
function confirmBooking(){const who=whoName(),guardian=who!=='Priya Raman';state.appt={status:'confirmed',time:state.booking.time,date:'Tue Sep 29',service:state.booking.service,clin:state.booking.clin,intake:false,onWaitlist:false,for:who};const q=me();q.status='confirmed';q.name=who;q.ini=initials(who);q.time=state.booking.time.replace(/ [ap]m/,'');state.pNotifs.unshift({t:`Booked${guardian?' for '+who.split(' ')[0]:''}: ${state.booking.service}, Tue Sep 29, ${state.booking.time}. Manage your visit from this link.`,s:'Just now · SMS + email',k:'good'});state.sAlerts.unshift({t:`New online booking: ${who}, ${state.booking.time} ${state.booking.clin} (${guardian?'booked by guardian Priya Raman':'guest'}, phone verified).`,s:'Just now',k:'info'});pgo('confirmed')}
function addFamily(){const name=$('#p-fam-name').value.trim();if(!name){toast('p','Enter their full name');$('#p-fam-name').focus();return}if(!$('#p-fam-ok').checked){toast('p','Confirm you can book for them');return}const f={id:'f'+Date.now(),name,rel:$('#p-fam-rel').value,dob:$('#p-fam-dob').value};state.family.push(f);state.booking.who=f.id;$('#p-fam-name').value='';$('#p-fam-dob').value='';$('#p-fam-ok').checked=false;toast('p',`${name.split(' ')[0]} added`);pgo(state.famFrom==='book'?'book':'family')}
function payBalance(){const owing=state.history.reduce((t,v)=>t+v.owing,0);state.history.forEach(v=>v.owing=0);state.sAlerts.unshift({t:`Priya Raman paid $${owing.toFixed(2)} online. Receipt emailed.`,s:'Just now',k:'good'});toast('p',`Paid $${owing.toFixed(2)}. Receipt emailed.`);renderPatient()}
function cancelAppt(){state.appt.status='cancelled';me().status='cancelled';state.sAlerts.unshift({t:'Priya Raman cancelled Tue 9:00 with Dr. Osei. Slot offered to waitlist (1 of 4).',s:'Just now',k:'warn'});state.pNotifs.unshift({t:'Your Tue 9:00 am visit is cancelled. The slot was offered to the waitlist.',s:'Just now · push',k:'mute'});toast('p','Visit cancelled. Slot released.');pgo('home')}
function joinWaitlist(){state.appt.onWaitlist=true;toast('p','On the waitlist. We\'ll text you first.');setTimeout(()=>pgo('offer'),1400)}
function acceptOffer(){state.appt.time='10:30 am';me().time='10:30';state.freedOffered=false;state.pNotifs.unshift({t:'Moved: your visit is now Tue Sep 29, 10:30 am with Dr. Osei.',s:'Just now · push + SMS',k:'good'});state.sAlerts.unshift({t:'Waitlist offer accepted: Priya Raman took the 10:30 slot. Recovery in 41 min.',s:'Just now',k:'good'});toast('p','Slot is yours');pgo('home')}
function submitIntake(){state.appt.intake=true;me().forms=true;toast('p','Form received. Front desk can see it.');pgo('home')}
function checkIn(){const q=me();q.status='waiting';q.since=0;state.sAlerts.unshift({t:'Priya Raman checked in from her phone (140 m away). Ticket A-15.',s:'Just now',k:'good'});toast('p','Checked in. Ticket A-15.');renderPatient()}

// ---------- staff ----------
function sfilter(f,btn){state.filter=f;$$('.seg button',btn.parentElement).forEach(b=>b.setAttribute('aria-pressed',b===btn));renderStaff()}
function setStatus(id,st){const q=state.queue.find(x=>x.id===id);const prev=q.status;q.status=st;if(st==='waiting')q.since=0;
  if(id===1){if(st==='invisit')state.pNotifs.unshift({t:'Dr. Osei is ready. Please go to Room 2.',s:'Just now · push',k:'info'});if(st==='done')state.appt.status='done';if(st==='noshow')state.appt.status='cancelled'}
  if(st==='noshow'){state.sAlerts.unshift({t:`${q.name} marked no-show for ${q.time}. Listed in Missed visits; slot released.`,s:'Just now',k:'crit'});
    state.missed.unshift({id:Date.now(),date:'Today',time:q.time+(+q.time.split(':')[0]<8||+q.time.split(':')[0]===12?' pm':' am'),name:q.name,clin:q.clin==='osei'?'Dr. Osei':q.clin==='lam'?'M. Lam':'Walk-in',svc:q.svc,reminder:q.status==='unconfirmed'?'Delivered, no reply':'Confirmed by SMS',prior:0,status:'open'})}
  toast('s',{waiting:'Arrived',invisit:'Called in',done:'Visit complete',noshow:'Marked no-show',late:'Marked late',confirmed:'Kept slot'}[st]||'Updated');renderStaff();renderPatient()}
function renderStaff(){
  const list=state.queue.filter(q=>state.filter==='all'||q.clin===state.filter).filter(q=>q.status!=='cancelled');
  const waiting=state.queue.filter(q=>q.status==='waiting').length;
  $('#s-count').textContent=`${waiting} waiting · ${state.queue.filter(q=>q.status==='invisit').length} in visit`;
  const late=state.queue.filter(q=>q.status==='late');const b=$('#s-banner');b.hidden=!late.length;b.textContent=late.length?`${late[0].name} is 12 min late. Text them or release the slot to the waitlist.`:'';
  const order={waiting:0,invisit:1,late:2,checked:3,confirmed:4,unconfirmed:5,booked:6,done:7,noshow:8};
  $('#s-queue').innerHTML=list.sort((a,b)=>order[a.status]-order[b.status]||a.time.localeCompare(b.time)).map(q=>{
    const cls={waiting:'waiting',invisit:'invisit',late:'late',checked:'checked'}[q.status]||'booked';
    let act='';
    if(q.status==='waiting')act=`<button class="btn sm primary" onclick="setStatus(${q.id},'invisit')">Call in</button>`;
    else if(q.status==='invisit')act=`<button class="btn sm primary" onclick="setStatus(${q.id},'done')">Complete</button>`;
    else if(q.status==='late')act=`<button class="btn sm" onclick="setStatus(${q.id},'waiting')">Arrived</button><button class="btn sm" onclick="toast('s','SMS sent: Running late? Reply to keep your slot.')">Text</button><button class="btn sm danger" onclick="setStatus(${q.id},'noshow')">No-show</button>`;
    else if(q.status==='done'||q.status==='noshow')act='';
    else act=`<button class="btn sm primary" onclick="setStatus(${q.id},'waiting')">Arrive</button>${q.status==='unconfirmed'?`<button class="btn sm" onclick="toast('s','Reminder resent by SMS')">Remind</button>`:''}${q.forms?'':`<button class="btn sm" onclick="toast('s','Form link sent by SMS')">Send form</button>`}`;
    return `<div class="qcard ${cls}"><div class="row between"><div class="row"><div class="avatar">${q.ini}</div><div><div style="font-weight:600">${q.name}</div><div class="small muted">${q.time} · ${q.svc} · ${q.clin==='osei'?'Dr. Osei':q.clin==='lam'?'M. Lam':'Walk-in'}</div></div></div>${pill(q.status)}</div><div class="row between"><span class="wait">${q.status==='waiting'?`waiting ${q.since??5} min · ticket ${q.ticket}`:q.status==='invisit'?`in room · ${q.since??8} min`:q.forms?'forms complete':'forms missing'}</span><button class="btn sm ghost" onclick="state.selectedPatient=${q.id};sgo('patient')">Details ›</button></div>${act?`<div class="actions">${act}</div>`:''}</div>`}).join('');
  $('#s-sched').innerHTML=state.queue.filter(q=>q.clin==='osei'&&q.status!=='cancelled').concat([{name:'Jordan Tremblay',time:'11:00',svc:'Physio follow-up',status:'confirmed',ini:'JT'},{name:'Daniel Okafor',time:'11:30',svc:'Physio follow-up',status:'booked',ini:'DO'}]).map(q=>`<div class="item"><span class="num muted" style="width:40px">${q.time}</span><div class="grow"><div class="t">${q.name}</div><div class="s">${q.svc}</div></div>${pill(q.status)}</div>`).join('');
  const p=state.queue.find(q=>q.id===state.selectedPatient);
  $('#s-patient').innerHTML=`<div class="card stack"><div class="row"><div class="avatar" style="width:44px;height:44px">${p.ini}</div><div><h3 style="font-size:18px">${p.name}</h3><div class="small muted">${p.time} · ${p.svc} · ticket ${p.ticket}</div></div><span style="margin-left:auto">${pill(p.status)}</span></div>
    <div class="grid2"><div class="tile"><span class="eyebrow">Forms</span><b style="font-size:15px">${p.forms?'Complete':'1 open'}</b></div><div class="tile"><span class="eyebrow">History</span><b style="font-size:15px">0 no-shows</b><span class="small">4 visits</span></div></div>
    ${p.id===1&&state.appt.for&&state.appt.for!=='Priya Raman'?'<div class="tile"><span class="eyebrow">Booked by guardian</span><p class="small" style="margin:4px 0 0">Priya Raman · +1 416 555 0142 gets reminders and offers for this visit.</p></div>':''}
    ${p.id===1&&state.appt.intake?'<div class="tile"><span class="eyebrow">Reason for visit (operational)</span><p class="small" style="margin:4px 0 0">Follow-up · lower back · "Prefer a ground-floor room, stairs are hard right now."</p></div>':''}
    <div class="actions"><button class="btn sm" onclick="toast('s','Booking link sent by SMS')">Send booking link</button><button class="btn sm" onclick="toast('s','Form link sent by SMS')">Resend forms</button><button class="btn sm" onclick="toast('s','Quick SMS: We are running 10 min behind, sorry.')">Quick text</button></div>
    <p class="small muted" style="margin:0">Contact details are visible to front desk and admin. Clinicians see only their own patients' operational info. Nothing clinical is stored here.</p></div>`;
  $('#s-freed').innerHTML=state.freedOffered?`<div class="row between"><div><p class="eyebrow">Freed slot · Dr. Osei</p><b>Tue 10:30 am</b><div class="small muted">Offered to Priya Raman · 14 min left · then Jordan T.</div></div><span class="pill warn">Offer out</span></div><div class="actions" style="margin-top:10px"><button class="btn sm" onclick="toast('s','Offer sent to all 3 matches')">Send to all matches</button><button class="btn sm" onclick="toast('s','Slot held for front desk')">Hold for phone</button></div>`:`<div class="row between"><div><p class="eyebrow">Freed slot · Dr. Osei</p><b>Tue 10:30 am</b><div class="small muted">Refilled by Priya Raman in 41 min</div></div><span class="pill good">Recovered</span></div>`;
  $('#s-alerts').innerHTML=state.sAlerts.map(n=>`<div class="item"><span class="pill ${n.k}" style="width:8px;height:8px;padding:0;border-radius:50%"></span><div class="grow"><div class="t" style="font-weight:500">${n.t}</div><div class="s">${n.s}</div></div></div>`).join('');
}

// ---------- web ----------
function renderWeb(){
  const rows=state.queue.filter(q=>!['cancelled','booked','unconfirmed'].includes(q.status)||q.id===1);
  $('#w-queue').innerHTML=`<tr><th>Ticket</th><th>Patient</th><th>Clinician</th><th>Appt</th><th>Status</th><th>Waited</th><th>Forms</th></tr>`+rows.map(q=>`<tr><td class="num" style="font-family:var(--mono)">${q.ticket}</td><td>${q.name}</td><td class="muted">${q.clin==='osei'?'Dr. Osei':q.clin==='lam'?'M. Lam':'Walk-in'}</td><td class="num">${q.time}</td><td>${pill(q.status)}</td><td class="num">${q.status==='waiting'?(q.since??5)+' min':q.status==='invisit'?'—':''}</td><td>${q.forms?'<span class="pill good">Done</span>':'<span class="pill warn">Open</span>'}</td></tr>`).join('');
  $('#w-kpi-wait').textContent=state.queue.filter(q=>q.status==='waiting').length;
  // calendar day
  const d=new Date(cur.calDate+'T00:00');
  $('#w-cal-date').textContent=d.toLocaleDateString('en-CA',{weekday:'long',month:'short',day:'numeric'});
  $('#w-cal-note').hidden=cur.calDate===CAL_BASE;
  // missed visits
  const M={open:['crit','Needs follow-up'],contacted:['warn','Contacted'],rebooked:['good','Rebooked'],excused:['mute','Excused']};
  const open=state.missed.filter(m=>m.status==='open').length;
  $('#w-missed-kpis').innerHTML=`<div class="kpi"><p class="eyebrow">Missed, 30 d</p><b class="num">${state.missed.length}</b><span class="delta muted">${state.missed.filter(m=>m.status==='excused').length} excused</span></div><div class="kpi"><p class="eyebrow">Need follow-up</p><b class="num">${open}</b><span class="delta" style="color:var(${open?'--warn':'--good'})">${open?'send a rebooking link':'all handled'}</span></div><div class="kpi"><p class="eyebrow">Rebooked</p><b class="num">${state.missed.filter(m=>m.status==='rebooked').length}</b><span class="delta muted">of ${state.missed.length} missed</span></div><div class="kpi"><p class="eyebrow">Repeat no-shows</p><b class="num">${state.missed.filter(m=>m.prior>0).length}</b><span class="delta muted">missed before</span></div>`;
  $$('#w-missed-filter button').forEach((b,i)=>b.setAttribute('aria-pressed',(i===0)===(state.missedFilter==='open')));
  const missedRows=state.missed.filter(m=>state.missedFilter==='all'||m.status==='open'||m.status==='contacted');
  $('#w-missed').innerHTML=`<tr><th>Missed</th><th>Patient</th><th>Clinician</th><th>Reminder</th><th>Status</th><th></th></tr>`+(missedRows.length?missedRows.map(m=>`<tr><td class="num" style="white-space:nowrap">${m.date} · ${m.time}</td><td>${m.name}${m.prior?` <span class="pill crit">${m.prior+1}× missed</span>`:''}<div class="small muted">${m.svc}</div></td><td class="muted">${m.clin}</td><td class="small">${m.reminder}</td><td><span class="pill ${M[m.status][0]}">${M[m.status][1]}</span></td><td style="white-space:nowrap">${m.status==='open'?`<button class="btn sm primary" onclick="missedAct(${m.id},'contacted')">Send rebooking link</button> <button class="btn sm" onclick="missedAct(${m.id},'excused')">Excuse</button>`:m.status==='contacted'?`<button class="btn sm" onclick="missedAct(${m.id},'rebooked')">Mark rebooked</button>`:''}</td></tr>`).join(''):'<tr><td colspan="6" class="muted">Nothing to follow up. Switch to All to see handled visits.</td></tr>');
  // unavailable time types
  $('#w-blocks').innerHTML='<tr><th>Type</th><th>Applies to</th><th>On the calendar</th><th></th></tr>'+state.blockTypes.map((b,i)=>`<tr><td>${b.name}</td><td class="muted">${b.scope}</td><td style="width:140px"><div class="appt off" style="height:22px">${b.name}</div></td><td style="text-align:right"><button class="btn sm" onclick="state.blockTypes.splice(${i},1);renderWeb();toast('w','Type removed')">Remove</button></td></tr>`).join('');
  // templates
  const pick=$('#w-tpl-pick');
  if(!pick.options.length)pick.innerHTML=Object.entries(state.tpls).map(([k,t])=>`<option value="${k}">${t.label}</option>`).join('');
  pick.value=state.tplPick;
  const ta=$('#w-tpl-text');if(document.activeElement!==ta)ta.value=state.tpls[state.tplPick].text;
  tplCount();
}
function tplCount(){const n=$('#w-tpl-text').value.length,seg=Math.ceil(n/160)||1;$('#w-tpl-count').textContent=`${n} characters before {placeholders} are filled · ${seg} SMS segment${seg>1?'s':''}${seg>1?' (costs more per message)':''}. Delivery log records channel, time and outcome for every message.`}
function saveTpl(){state.tpls[state.tplPick].text=$('#w-tpl-text').value;tplCount()}
function calShift(n){const d=new Date((n?cur.calDate:CAL_BASE)+'T00:00');d.setDate(d.getDate()+n);cur.calDate=d.toLocaleDateString('en-CA');syncHash();renderWeb()}
function missedAct(id,st){const m=state.missed.find(x=>x.id===id);m.status=st;toast('w',{contacted:`Rebooking link sent to ${m.name.split(' ')[0]} by SMS`,excused:'Excused. Not counted in the no-show rate',rebooked:'Marked rebooked'}[st]);renderWeb()}
function addBlockType(){const el=$('#w-block-name'),name=el.value.trim();if(!name){toast('w','Name the type first');el.focus();return}state.blockTypes.push({name,scope:$('#w-block-who').value});el.value='';toast('w',`${name} added`);renderWeb()}
function renderAll(){renderPatient();renderStaff();renderWeb()}
renderAll();
openFromHash();
