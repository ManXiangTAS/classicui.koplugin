# �ع����

������Ҫ�ٷ� KOReader Linux ģ��������Ŀ¼������ luajit �� SDL �⣩�������� `plugins/einkfrontend.koplugin` ���ӵ����ֿ���Ŀ¼������ʹ�ø������ú�ԭ��ʾ���鼮�����޸���ʵ��⡣

```sh
python3 tests/run_regression.py /path/to/koreader
```

���� `--suite core` �Ȳ�������ָ���顣���Ǽ۸���Ԫ���ݡ�����Ǩ�ơ���������������������������Ӣ���롢ԭ���ؼ�����ҳ�����������ò˵����Զ�ǰ�⡣

`--suite maintenance` ʹ�ø������͸����ļ���֤ɾ��ȷ�ϡ�ȡ����ʧ�ܡ��Ѵ򿪱������Լ�����ɨ�衢Ԥ����ָ���ͬ�����ʽ������ / ��ϣԪ���ݡ��������ݿ⡢·�����ӡ��洢�仯�����ԡ�ԭʼʾ��������ʷͳ�Ʊ��ֲ��䡣

�Զ�ǰ������ߡ����䡢�ֶ����ȡ�Ӳ����洢���ϡ����ߵȲ��Լ����� LuaJIT ����ִ�У�`luajit tests/test_light_policy.lua`��`--suite autolight` ʹ��ģ�⴫��������ʵ KOReader ���á�Powerd �ͽ��棬��֤��ڡ�У׼Ԥ����ȡ������д���á����ߺ��Ķ����أ��ⲻ�����ʵ����빦�Ĳ��ԡ�

�����������Ҫ Node.js��Playwright �� Chromium������ `EINK_CHROMIUM` Ϊ�����·����

```sh
npm install --prefix tests
EINK_CHROMIUM=/path/to/chromium python3 tests/run_web.py /path/to/koreader upload
EINK_CHROMIUM=/path/to/chromium python3 tests/run_web.py /path/to/koreader home_editor
```

��־�뻭����������Ե� `test-results/`��������Դ���밲װ������ʵ Kindle ����ʾ��Ӳ����������ʵ����顣

��������Ĭ��ֻ���ɲݸ塣ά����ȷ�Ϻ󣬿��ֶ����й�������ѡ��������ʹ���뵱ǰ�汾��ȫһ�µ��ύ���� `Release ClassicUI <�汾��>`����ͨ���Ͳ��ṫ���°汾���������Լ�飺`python3 tests/test_release_policy.py`��

## ���������߼���飨0.7.3��

��Ҫ Python��Node.js���Լ���װ�� tests/node_modules �� Fengari��

    npm install --prefix tests
    python tests/run_local_checks.py

Ҳ�ɽ� FENGARI_ROOT ����Ϊ���� Fengari �� src Ŀ¼�������ظ��������������в������� GitHub���޸���ʵ��������豸Ӳ������������ʹ���ڴ� HTTP ��������ҳ���ʹ�� Node VM �ͼ� DOM/HTTP ������Lua ���ʹ�� Fengari Lua 5.3��

�����鸲�Ƿ������ԡ���װ��������/ժҪ/�ظ�������ԭǰ����ԡ�����ע������ҳ�ű��߼������λ�� test-results/local/combined-summary.json�������ܴ����������� LuaJIT��SDL/crengine/MuPDF ģ������Playwright ����������� Kindle ������ԡ�

���� test_light_upgrade.lua ��֤�ɵ����ߡ�����Ŀ��仯����ֶ��ָ�����������/1 �븴�顢�򻯺�����õ���������У�飬�Լ�����λ�ڻ������Ϸ��Ļ������ꡣ�˻��Ƽ��ʹ������������֤��ʵ����դ��
