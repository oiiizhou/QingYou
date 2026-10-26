# 参与轻右开发

欢迎修复问题、补充设备验证、改善中文文案与使用说明。项目使用 MIT 许可，提交的代码与资源需有明确来源。

## 开始开发

源码工程位于 `QingYou/`；若单独克隆工程内容，它就是仓库根目录。先进入包含 `Sources/`、`Resources/` 和 `scripts/` 的目录。

```bash
bash scripts/build.sh
bash scripts/test.sh
python3 scripts/verify_project.py
python3 scripts/verify_templates.py
python3 scripts/verify_docs.py
```

需要 Xcode Command Line Tools 或完整 Xcode。日常构建无第三方运行时和 Python 包要求；仅重新生成办公模板需要架构文档中列出的开发依赖。

## 修改约定

- 保留 Finder 就近完成的工作方式；复杂任务使用独立原生窗口。
- 复用系统控件、字体、语义色和现有设计系统，不增加装饰渐变与厚阴影。
- 文件算法与界面分离；后台预览丢弃过期结果，耗时任务支持取消。
- 测试使用独立临时目录及独立剪贴板，不访问个人工作文件，不修改真实登录项或权限。
- 新输出不覆盖原件；失败回滚只清理本次创建且身份一致的文件。
- 中文注释解释约束与原因，避免重复代码字面含义。
- 功能变化同步 README、更新记录和验证范围；不把未验证的平台、手势或权限写成已通过。

## 报告问题与提交 PR

报告中提供轻右版本、macOS 版本、芯片、入口、复现步骤、预期和实际结果。若涉及 PDF／图片，可提供不含个人数据的最小样例；不要上传真实操作历史、私密文档、位置元数据、证书或凭据。

PR 说明应包含具体问题、行为变化、验证结果与限制。界面修改附明暗及紧凑尺寸截图；文件操作修改核对实际输出和原件。提交前检查没有 `build/`、`dist/` 或个人绝对路径。

## 文档维护

工程 README 是唯一正文来源，外层首页由脚本同步：

```bash
python3 scripts/sync_readme.py
python3 scripts/sync_readme.py --check
```

独立工程模式会自动跳过父目录同步。源码上传、预览包与签名公证流程见 [发布指南](docs/RELEASING.md)。
