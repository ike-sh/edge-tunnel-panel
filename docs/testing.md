# 测试与 release 验证

Leikwan Toolkit 1.2.1 增加正式回归测试入口，用于发布前检查 CLI、渲染、打包和脱敏边界。

## 一键验证

```bash
bash scripts/verify-release.sh
```

它会按顺序执行：

```bash
bash -n leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
shellcheck leikwan-toolkit.sh scripts/package-release.sh scripts/check-redaction.sh scripts/bootstrap.sh
git diff --check
bash scripts/check-redaction.sh
bash tests/smoke.sh
bash tests/cli-regression.sh
bash tests/render-regression.sh
bash tests/package-regression.sh
bash tests/redaction-regression.sh
bash scripts/package-release.sh
```

任一步失败都会退出非零。全部通过时输出：

```text
[OK] release verification passed
```

## 单项测试

```bash
bash tests/smoke.sh
bash tests/cli-regression.sh
bash tests/render-regression.sh
bash tests/package-regression.sh
bash tests/redaction-regression.sh
```

- `smoke.sh`：基础语法、版本、帮助和关键 CLI 参数识别。
- `cli-regression.sh`：只读 CLI 在空状态目录下不触发全局 trap。
- `render-regression.sh`：模拟 TSV，检查表格和紧凑渲染。
- `package-regression.sh`：检查 release 包内容边界。
- `redaction-regression.sh`：检查脱敏、端点 HTML 转义、恶意 tar 拒绝。

测试脚本会使用临时 `LEIKWAN_STATE_DIR`，不会修改真实 `/etc/leikwan-toolkit`。

## 服务器验收

发布包生成后，在真实测试机继续执行：

```bash
lq status
lq --doctor
lq port check
lq ddns status
lq pbr domain list
```

有完整 B 侧配置时，继续检查：

```bash
lq output generate
lq output json
lq output html
lq config export --redacted
```

有维护窗口时再检查高危路径：

```bash
nohup lq forward apply-relay --auto-fix-route >/root/lq-apply-relay.log 2>&1 &
lq config import /root/leikwan-config-YYYYMMDD-HHMMSS.tar.gz
```
