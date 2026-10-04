# Example workflows / 使用示例

After installation, select your own Local Computer Assistant plugin in a **new ordinary ChatGPT Chat**. Replace these generic paths with your own files. Start with disposable copies.

The model should call `begin_task`, pass its `task_id` to subsequent tools, read existing files before saving, and call `end_task` after its processes finish. You do not need to copy a task ID between chats.

## Explore and summarize

> Search D:\Research for Markdown and text notes about my topic. Read relevant files, summarize the evidence, and save the summary to D:\Research\summary.md. Cite local filenames so I can check the sources.

> 在 D:\Research 中查找与我的研究主题有关的笔记，读取内容，按原文件名引用，并把总结保存为 summary.md。

PDF, Word, spreadsheets, and statistical files may require an appropriate local parser or installed application. The model can use command tools to run available software; the kit does not install every document application.

## Edit and save

> Read D:\Projects\notes.md, fix unclear sentences, preserve headings, and save the result. If another task changed the file, reread it and merge my edits. Show the saved path.

> 读取 D:\Projects\notes.md，修改表达并保留标题。保存前处理版本冲突，完成后重新读取检查。

## Run a script

> Run my existing Python script against disposable input files. Return the process ID promptly, poll its output, and save generated results in this task's work directory. Before updating an existing destination file, read its current version and use commit_file to save the working copy.

> 运行本机已有脚本，长任务先返回 PID，再分次查看输出。先生成工作副本，检查目标文件最新内容后使用 commit_file 写回。

## Two chats at once

> Start an independent task for this chat. Work on my requested files using your own task ID, process IDs, and search IDs. If a file reports FILE_CONFLICT, reread and merge instead of forcing a stale overwrite.

Each task has separate processes and state. Commands that directly write the same file bypass gateway file checks; use separate working copies and coordinate the final save.

## Verify the connection

Run `New-ChatVerification.ps1` from the private runtime. Paste its generated prompt into ordinary Chat, wait for completion, then run `Confirm-ChatVerification.ps1` locally. Require `verified=true` before considering setup complete.
