import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { readFile, writeFile, mkdir, unlink, access } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { randomUUID } from 'node:crypto';
const settingsFile=path.resolve(process.argv[2]);
const root=path.dirname(settingsFile);
const settings=JSON.parse((await readFile(settingsFile,'utf8')).replace(/^\uFEFF/,''));
const sandbox=path.join(root,'sandbox');await mkdir(sandbox,{recursive:true});
const configHome=settings.configHome||os.homedir();await mkdir(configHome,{recursive:true});
const testPath=path.join(settings.accessMode==='Full'?root:settings.allowedDirectories[0],`assistant-check-${randomUUID()}.txt`);
const client=new Client({name:'local-assistant-installer',version:'1.0.0'});
const env={...process.env,DESKTOP_COMMANDER_DISABLE_TELEMETRY:'1'};
if(settings.configHome)env.USERPROFILE=configHome;
const transport=new StdioClientTransport({command:settings.nodeExecutable,args:[path.join(root,'node_modules/@wonderwhy-er/desktop-commander/dist/index.js'),'--no-onboarding'],cwd:sandbox,env,stderr:'pipe'});
const call=async(name,args)=>{const r=await client.callTool({name,arguments:args});if(r.isError)throw Error(`Local MCP ${name} failed. Inspect privately; no credential or file content is printed.`);return r;};
let created=false;
try {
 await client.connect(transport);
 const backup=path.join(root,'local-settings-backup.json');
 try {await access(backup);}catch {
  const original=JSON.parse(await readFile(path.join(configHome,'.claude-server-commander/config.json'),'utf8'));
  await writeFile(backup,JSON.stringify({allowedDirectories:original.allowedDirectories,blockedCommands:original.blockedCommands},null,2));
 }
 await call('set_config_value',{key:'allowedDirectories',value:settings.accessMode==='Full'?[]:settings.allowedDirectories});
 if(settings.accessMode==='Full')await call('set_config_value',{key:'blockedCommands',value:[]});
 await call('set_config_value',{key:'telemetryEnabled',value:false});
 const {tools}=await client.listTools();
 const config=JSON.parse(await readFile(path.join(configHome,'.claude-server-commander/config.json'),'utf8'));
 if(settings.accessMode==='Full'&&(config.allowedDirectories.length||config.blockedCommands.length))throw Error('Full scope was not persisted.');
 await call('write_file',{path:testPath,content:'LOCAL_ASSISTANT_ORIGINAL\n'});created=true;
 if(!JSON.stringify(await call('read_file',{path:testPath})).includes('LOCAL_ASSISTANT_ORIGINAL'))throw Error('Local read verification failed.');
 await call('edit_block',{file_path:testPath,old_string:'LOCAL_ASSISTANT_ORIGINAL',new_string:'LOCAL_ASSISTANT_VERIFIED'});
 if(!(await readFile(testPath,'utf8')).includes('LOCAL_ASSISTANT_VERIFIED'))throw Error('Local saved edit verification failed.');
 const processResult=await call('start_process',{command:settings.accessMode==='Full'?'reg /?':'Write-Output "LOCAL_ASSISTANT_PROCESS_OK"',timeout_ms:10000});
 const expected=settings.accessMode==='Full'?'REG':'LOCAL_ASSISTANT_PROCESS_OK';
 if(!JSON.stringify(processResult).includes(expected))throw Error('Local process verification failed.');
 await unlink(testPath);created=false;
 const report={localVerified:true,accessMode:settings.accessMode,toolCount:tools.length,read:true,write:true,edit:true,process:true,chatVerified:false,at:new Date().toISOString()};
 await writeFile(path.join(root,'local-verification.private.json'),JSON.stringify(report,null,2));
 console.log(JSON.stringify(report));
} finally {await client.close();if(created)await unlink(testPath);}
