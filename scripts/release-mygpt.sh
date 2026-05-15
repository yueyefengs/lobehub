#!/usr/bin/env bash
# ============================================
# MyGPT 桌面端发版脚本
# ============================================
# 用法:
#   ./scripts/release-mygpt.sh 1.0.0
#   ./scripts/release-mygpt.sh 1.2.3-beta.1
#
# 流程:
#   1. 校验：工作区干净 / 版本号格式 / tag 未被占用
#   2. 切换到 canary 分支
#   3. rebase 拉取最新代码
#   4. 推送 canary（如有本地领先提交）
#   5. 创建带签名的 annotated tag (mygpt-v<version>)
#   6. 推送 tag 到 origin（触发 GitHub Actions 自动构建）
# ============================================

set -euo pipefail

# ---------- 输入校验 ----------
if [ $# -ne 1 ]; then
  echo "❌ 用法: $0 <版本号>"
  echo "   示例: $0 1.0.0"
  echo "        $0 1.2.3-beta.1"
  exit 1
fi

VERSION="${1#v}"           # 兼容 v1.0.0 / 1.0.0 两种写法
VERSION="${VERSION#mygpt-v}"
TAG="mygpt-v${VERSION}"

# 语义化版本号校验（x.y.z 必填，prerelease 可选）
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
  echo "❌ 版本号格式错误: $VERSION"
  echo "   期望: x.y.z 或 x.y.z-prerelease （如 1.0.0 / 1.0.0-beta.1）"
  exit 1
fi

echo "🎯 准备发版: $TAG"
echo ""

# ---------- 工作区检查 ----------
if ! git diff-index --quiet HEAD --; then
  echo "❌ 工作区有未提交改动，请先 commit 或 stash"
  git status -s
  exit 1
fi

# ---------- tag 占用检查 ----------
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "❌ Tag $TAG 已存在于本地"
  echo "   如需重发，先执行: git tag -d $TAG && git push origin :refs/tags/$TAG"
  exit 1
fi

echo "🔍 检查远端 tag 是否被占用..."
if git ls-remote --tags origin "refs/tags/$TAG" | grep -q "refs/tags/$TAG"; then
  echo "❌ Tag $TAG 已存在于远端 origin"
  exit 1
fi

# ---------- 切到 canary 拉最新 ----------
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "🔄 当前分支: $CURRENT_BRANCH → 切换到 canary"
git checkout canary

echo "⬇️  从 origin/canary 拉取最新代码（rebase）..."
git pull --rebase origin canary

# ---------- 推送 canary（如有本地领先提交）----------
LOCAL_AHEAD=$(git rev-list --count "origin/canary..canary")
if [ "$LOCAL_AHEAD" -gt 0 ]; then
  echo "📤 本地 canary 领先远端 $LOCAL_AHEAD 个提交，推送中..."
  git push origin canary
else
  echo "✅ canary 已与远端同步"
fi

# ---------- 打 tag ----------
echo "🏷️  创建 tag: $TAG"
git tag -a "$TAG" -m "Release $TAG"

# ---------- 推送 tag ----------
echo "🚀 推送 tag 到 origin（这会触发 GitHub Actions 构建）..."
git push origin "$TAG"

# ---------- 完成提示 ----------
REMOTE_URL=$(git remote get-url origin)
REPO_PATH=$(echo "$REMOTE_URL" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')

echo ""
echo "✅ 发版完成！"
echo ""
echo "   Tag:       $TAG"
echo "   Actions:   https://github.com/${REPO_PATH}/actions"
echo "   Release:   https://github.com/${REPO_PATH}/releases/tag/${TAG}（构建完成后可见）"
echo ""
echo "   构建大约需要 30-60 分钟（macOS 占大头），完成后产物会自动出现在 Release 页面。"
