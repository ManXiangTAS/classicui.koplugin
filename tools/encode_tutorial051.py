from pathlib import Path
import json,subprocess,math
P=Path(__file__).resolve().parents[1];O=P.parent/'deliverables051';F=O/'tutorial-frames';scenes=json.loads((F/'scenes.json').read_text());rec=json.loads((P/'test-results-051/tutorial-recording.json').read_text());clip_seconds=41
for name,items in [('part-a',list(enumerate(scenes[:15]))),('part-b',list(enumerate(scenes[15:],15)))]:
 text=''.join("file '"+str(F/f'{i:03d}.png')+"'\nduration "+str(s['duration'])+'\n' for i,s in items);text+="file '"+str(F/f'{items[-1][0]:03d}.png')+"'\n";(F/(name+'.txt')).write_text(text)
# Guide timestamp anchors include the inserted browser recording.
first=sum(s['duration'] for s in scenes[:15]);cursor=0;chapters=[]
for i,s in enumerate(scenes):
 if i==15:chapters.append({'title':'网页传书实际录屏','start':cursor});cursor+=clip_seconds
 if not chapters or chapters[-1]['title']!=s['chapter']:chapters.append({'title':s['chapter'],'start':cursor})
 cursor+=s['duration']
metadata=';FFMETADATA1\ntitle=墨页 0.5.0 安装与使用完整字幕教程\ncomment=字幕教程无配音；原生界面为真实KOReader桌面模拟；网页传书部分为实际操作录屏。\n'
for i,c in enumerate(chapters):metadata+=f'\n[CHAPTER]\nTIMEBASE=1/1000\nSTART={c["start"]*1000}\nEND={(chapters[i+1]["start"] if i+1<len(chapters) else cursor)*1000}\ntitle={c["title"]}\n'
(F/'final-chapters.ffmeta').write_text(metadata)
clips=[]
for i,scene in enumerate(scenes):
 target=F/f'clip-{i:03d}.mp4';seconds=scene['duration'];clips.append(target)
 probe=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',str(target)],capture_output=True,text=True) if target.exists() else None
 if probe and probe.returncode==0 and abs(float(probe.stdout.strip())-seconds)<.1:continue
 print(f'Encoding slide {i+1}/{len(scenes)}',flush=True)
 subprocess.run(['ffmpeg','-y','-hide_banner','-loglevel','error','-threads','1','-loop','1','-framerate','1','-i',str(F/f'{i:03d}.png'),'-t',str(seconds),'-vf','fps=15,format=yuv420p','-c:v','libx264','-preset','ultrafast','-crf','23','-threads','1','-filter_threads','1','-x264-params','rc-lookahead=0:bframes=0:ref=1','-video_track_timescale','90000',str(target)],check=True)
print('Encoding actual browser recording',flush=True)
subprocess.run(['ffmpeg','-y','-hide_banner','-loglevel','error','-threads','1','-i',rec['file'],'-vf','scale=1554:1080,pad=1920:1080:183:0:color=0xf7f8f8,fps=15,tpad=stop_mode=clone:stop_duration=3,format=yuv420p','-t',str(clip_seconds),'-c:v','libx264','-preset','ultrafast','-crf','23','-threads','1','-filter_threads','1','-x264-params','rc-lookahead=0:bframes=0:ref=1','-video_track_timescale','90000',str(F/'browser.mp4')],check=True)
ordered=clips[:15]+[F/'browser.mp4']+clips[15:]
(F/'assemble.txt').write_text(''.join("file '"+str(path)+"'\n" for path in ordered))
final=O/'墨页_0.5.0_安装与使用教程.mp4';subprocess.run(['ffmpeg','-y','-hide_banner','-loglevel','error','-f','concat','-safe','0','-i',str(F/'assemble.txt'),'-i',str(F/'final-chapters.ffmeta'),'-map_metadata','1','-map_chapters','1','-c','copy','-movflags','+faststart',str(final)],check=True)
info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_format','-show_streams','-show_chapters','-of','json',str(final)]));assert abs(float(info['format']['duration'])-cursor)<1;assert info['streams'][0]['width']==1920 and info['streams'][0]['height']==1080
summary={'file':final.name,'seconds':float(info['format']['duration']),'resolution':'1920x1080','captions':'Burned-in Chinese instructional captions; no narration','scenes':len(scenes),'browser_recording_seconds':41,'chapters':[{'title':c['tags']['title'],'start':float(c['start_time'])} for c in info['chapters']],'native':'Actual KOReader desktop emulator captures; physical device not filmed'};(P/'test-results-051/tutorial-video.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n');print(summary,flush=True)
