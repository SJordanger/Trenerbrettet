/* Trenerbrettet v60 – datadrevet spillformkonfigurasjon.
 * 3-er, 5-er, 7-er, 9-er og 11-er er aktivert.
 * 11-er inkluderer avanserte formasjoner med wingbacker, defensiv/offensiv midtbane og vingroller.
 */
(function(){
  'use strict';
  const all = Object.freeze([
    {id:3,label:'3-er',playerCount:3,defaultMinutes:15,defaultPeriods:2,hasGoalkeeper:false,enabled:true,formations:['3','2-1','1-1-1'],benchMax:8},
    {id:5,label:'5-er',playerCount:5,defaultMinutes:25,defaultPeriods:2,hasGoalkeeper:true,enabled:true,formations:['1-2-1','2-2','3-1'],benchMax:8},
    {id:7,label:'7-er',playerCount:7,defaultMinutes:30,defaultPeriods:2,hasGoalkeeper:true,enabled:true,formations:['2-3-1','3-2-1','3-1-2'],benchMax:8},
    {id:9,label:'9-er',playerCount:9,defaultMinutes:35,defaultPeriods:2,hasGoalkeeper:true,enabled:true,formations:['3-4-1','4-3-1','3-3-2','2-4-2'],benchMax:8},
    {id:11,label:'11-er',playerCount:11,defaultMinutes:45,defaultPeriods:2,hasGoalkeeper:true,enabled:true,formations:['4-4-2','4-4-2 D','4-5-1','5-3-2','4-3-3','3-5-2','4-2-3-1'],benchMax:8,ageDurations:[{age:'14 år',minutes:35},{age:'15–16 år',minutes:40},{age:'17 år og eldre',minutes:45}]}
  ].map(x=>Object.freeze(x)));
  window.TRENERBRETTET_FORMATS=Object.freeze({version:1,all,get:(id)=>all.find(x=>x.id===Number(id))||null});
})();
