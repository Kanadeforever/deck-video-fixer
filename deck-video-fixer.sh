#!/usr/bin/env bash
# Deck Video Fixer - Steam Deck/Linux edition
# GUI: kdialog/zenity when available, terminal fallback.
# Core dependencies: ffmpeg + ffprobe. Optional bundled binaries: ./bin/ffmpeg ./bin/ffprobe

set -u

TOOL_VERSION="0.3.2"
BACKUP_DIR_NAME=".deck-video-fixer-backup"
MANIFEST_NAME="manifest.tsv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer bundled ffmpeg/ffprobe if a future release ships them next to this script.
if [[ -x "$SCRIPT_DIR/bin/ffmpeg" ]]; then
  FFMPEG="$SCRIPT_DIR/bin/ffmpeg"
else
  FFMPEG="$(command -v ffmpeg || true)"
fi
if [[ -x "$SCRIPT_DIR/bin/ffprobe" ]]; then
  FFPROBE="$SCRIPT_DIR/bin/ffprobe"
else
  FFPROBE="$(command -v ffprobe || true)"
fi

HAS_KDIALOG=0
HAS_ZENITY=0
command -v kdialog >/dev/null 2>&1 && HAS_KDIALOG=1
command -v zenity >/dev/null 2>&1 && HAS_ZENITY=1

# Directory picker style. Steam Deck's native kdialog folder chooser can be awkward
# because it may not expose an address/location bar. The default therefore asks
# for a pasteable path first, then offers the system picker as a fallback.
# Valid values: auto, input, native, kdialog, zenity, terminal
PVF_PICKER="${PVF_PICKER:-auto}"
PVF_GAME_DIR="${PVF_GAME_DIR:-${GAME_DIR:-}}"
# Transcode strategy. Valid values:
#   recommended, h264_quality, h264_balanced, h264_fast, h264_small, h264_baseline, webm_vp9, mpeg_mci, mpeg2_mpg
# Legacy aliases are still accepted: modern => h264_quality, h264 => h264_quality, mp4 => h264_quality.
PVF_TRANSCODE_MODE="${PVF_TRANSCODE_MODE:-recommended}"
# Backup handling after a successful conversion. Valid values: ask, keep, delete.
# Default is ask; the delete path is only offered when all selected files converted successfully.
PVF_BACKUP_AFTER_SUCCESS="${PVF_BACKUP_AFTER_SUCCESS:-ask}"

ui_info() {
  local msg="$1"
  if [[ $HAS_KDIALOG -eq 1 ]]; then
    kdialog --msgbox "$msg" 2>/dev/null || true
  elif [[ $HAS_ZENITY -eq 1 ]]; then
    zenity --info --text="$msg" 2>/dev/null || true
  else
    printf '\n%s\n' "$msg"
  fi
}

ui_error() {
  local msg="$1"
  if [[ $HAS_KDIALOG -eq 1 ]]; then
    kdialog --error "$msg" 2>/dev/null || true
  elif [[ $HAS_ZENITY -eq 1 ]]; then
    zenity --error --text="$msg" 2>/dev/null || true
  else
    printf '\nERROR: %s\n' "$msg" >&2
  fi
}

ui_yesno() {
  local msg="$1"
  if [[ $HAS_KDIALOG -eq 1 ]]; then
    kdialog --yesno "$msg" 2>/dev/null
    return $?
  elif [[ $HAS_ZENITY -eq 1 ]]; then
    zenity --question --text="$msg" 2>/dev/null
    return $?
  else
    printf '\n%s [y/N]: ' "$msg"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
    return $?
  fi
}

ui_textbox() {
  local title="$1"
  local file="$2"
  if [[ $HAS_KDIALOG -eq 1 ]]; then
    kdialog --title "$title" --textbox "$file" 900 650 2>/dev/null || true
  elif [[ $HAS_ZENITY -eq 1 ]]; then
    zenity --text-info --title="$title" --filename="$file" --width=900 --height=650 2>/dev/null || true
  else
    printf '\n==== %s ====\n' "$title"
    cat "$file"
    printf '\n==== End ====\n'
  fi
}

normalize_dir() {
  local dir="$1"
  # Trim common quoting/whitespace from pasted paths.
  dir="${dir#\"}"
  dir="${dir%\"}"
  dir="${dir#\'}"
  dir="${dir%\'}"
  dir="${dir/#\~/$HOME}"
  [[ -n "$dir" && -d "$dir" ]] || return 1
  realpath "$dir"
}

choose_directory_input() {
  local dir="" prompt default_path
  default_path="${PVF_LAST_DIR:-${PVF_GAME_DIR:-$HOME}}"
  prompt=$'粘贴或输入游戏文件夹路径：\n\nSteam 里也可以：齿轮/右键游戏 → 管理 → 浏览本地文件，然后从 Dolphin 地址栏复制路径。\n\n留空会打开系统文件夹选择器。'

  if [[ $HAS_KDIALOG -eq 1 ]]; then
    dir="$(kdialog --title "选择游戏文件夹" --inputbox "$prompt" "$default_path" 2>/dev/null || true)"
  elif [[ $HAS_ZENITY -eq 1 ]]; then
    dir="$(zenity --entry --title="选择游戏文件夹" --text="$prompt" --entry-text="$default_path" --width=760 2>/dev/null || true)"
  else
    printf '输入游戏文件夹路径；留空取消: ' >&2
    read -r dir
  fi

  if [[ -z "$dir" ]]; then
    return 2
  fi
  normalize_dir "$dir"
}

choose_directory_native() {
  local dir=""
  if [[ $HAS_ZENITY -eq 1 && ( "$PVF_PICKER" == "zenity" || "$PVF_PICKER" == "native" || "$PVF_PICKER" == "auto" ) ]]; then
    dir="$(zenity --file-selection --directory --title="选择游戏文件夹" 2>/dev/null || true)"
  elif [[ $HAS_KDIALOG -eq 1 && ( "$PVF_PICKER" == "kdialog" || "$PVF_PICKER" == "native" || "$PVF_PICKER" == "auto" ) ]]; then
    dir="$(kdialog --getexistingdirectory "$HOME" "选择游戏文件夹" 2>/dev/null || true)"
  else
    printf '输入游戏文件夹路径: ' >&2
    read -r dir
  fi

  [[ -n "$dir" ]] || return 1
  normalize_dir "$dir"
}

choose_directory() {
  local dir=""

  # Command line / environment shortcut. Examples:
  #   ./deck-video-fixer.sh "/path/to/game"
  #   PVF_GAME_DIR="/path/to/game" ./deck-video-fixer.sh
  if [[ -n "${1:-}" ]]; then
    normalize_dir "$1" && return 0
  fi
  if [[ -n "$PVF_GAME_DIR" ]]; then
    normalize_dir "$PVF_GAME_DIR" && return 0
  fi

  case "$PVF_PICKER" in
    input)
      choose_directory_input
      return $?
      ;;
    native|kdialog|zenity)
      choose_directory_native
      return $?
      ;;
    terminal)
      printf '输入游戏文件夹路径: ' >&2
      read -r dir
      normalize_dir "$dir"
      return $?
      ;;
    auto|*)
      # Default: a pasteable path input is usually faster on Steam Deck than
      # kdialog's folder tree. If the user leaves it blank, fall back to native.
      dir="$(choose_directory_input)"
      case $? in
        0) printf '%s\n' "$dir"; return 0 ;;
        2) choose_directory_native; return $? ;;
        *) return 1 ;;
      esac
      ;;
  esac
}

choose_action() {
  if [[ $HAS_KDIALOG -eq 1 ]]; then
    kdialog --menu "Deck Video Fixer" \
      convert "扫描并转码修复 Proton 兼容性问题视频" \
      restore "从备份还原" \
      quit "退出" 2>/dev/null || echo quit
  elif [[ $HAS_ZENITY -eq 1 ]]; then
    local result
    result="$(zenity --list --title="Deck Video Fixer" --column="动作" --column="说明" \
      convert "扫描并转码修复 Proton 兼容性问题视频" \
      restore "从备份还原" \
      quit "退出" --height=260 --width=520 2>/dev/null || echo quit)"
    printf '%s\n' "$result"
  else
    printf '\n1) 扫描并转码修复 Proton 兼容性问题视频\n2) 从备份还原\n3) 退出\n选择: ' >&2
    read -r n
    case "$n" in
      1) echo convert ;;
      2) echo restore ;;
      *) echo quit ;;
    esac
  fi
}


normalize_transcode_mode() {
  case "${1:-}" in
    recommended|auto|recommend|suggested|"") echo "recommended" ;;
    h264_quality|quality|modern|h264|h264_aac|mp4) echo "h264_quality" ;;
    h264_balanced|balanced|default) echo "h264_balanced" ;;
    h264_fast|fast|speed) echo "h264_fast" ;;
    h264_small|small|compact|size) echo "h264_small" ;;
    h264_baseline|baseline|compat|compatibility) echo "h264_baseline" ;;
    webm_vp9|vp9|webm) echo "webm_vp9" ;;
    mpeg_mci|mpeg|mpg|mci) echo "mpeg_mci" ;;
    mpeg2_mpg|mpeg2|dvd) echo "mpeg2_mpg" ;;
    *) echo "recommended" ;;
  esac
}

transcode_mode_label() {
  case "$1" in
    h264_quality) echo "H.264/AAC 高质量：CRF 18，兼容性好，体积较大，保留原文件名" ;;
    h264_balanced) echo "H.264/AAC 均衡：CRF 22，速度/体积/画质折中，保留原文件名" ;;
    h264_fast) echo "H.264/AAC 快速：CRF 20 + veryfast，速度优先，文件可能更大" ;;
    h264_small) echo "H.264/AAC 小体积：CRF 27，适合节省空间，画质会下降" ;;
    h264_baseline) echo "H.264/AAC 旧解码器兼容：Baseline profile，适合极旧播放器链路，保留原文件名" ;;
    webm_vp9) echo "WebM VP9/Opus 绕过：部分游戏视频链可用，失败概率比 H.264 高" ;;
    mpeg_mci) echo "旧 MPG/MCI：MPEG-1 Video + MP2 Audio + MPEG 容器，适合旧 .mpg/.mpeg" ;;
    mpeg2_mpg) echo "MPEG-2/MP2：DVD-era MPG 备用，仍是真 MPEG 容器" ;;
    recommended|*) echo "使用扫描推荐：MPG/MPEG 倾向 mpeg_mci，其余易出问题文件倾向 h264_quality" ;;
  esac
}

transcode_mode_short_label() {
  case "$1" in
    h264_quality) echo "H.264 高质量" ;;
    h264_balanced) echo "H.264 均衡" ;;
    h264_fast) echo "H.264 快速" ;;
    h264_small) echo "H.264 小体积" ;;
    h264_baseline) echo "H.264 Baseline" ;;
    webm_vp9) echo "WebM VP9" ;;
    mpeg_mci) echo "旧 MPG/MCI" ;;
    mpeg2_mpg) echo "MPEG-2 MPG" ;;
    recommended|*) echo "扫描推荐" ;;
  esac
}

choose_transcode_mode() {
  local mode supplied
  supplied="${PVF_TRANSCODE_MODE:-}"
  mode="$(normalize_transcode_mode "$supplied")"

  # If the user explicitly supplied a concrete mode, respect it without showing another dialog.
  case "$supplied" in
    h264_quality|quality|modern|h264|h264_aac|mp4|h264_balanced|balanced|default|h264_fast|fast|speed|h264_small|small|compact|size|h264_baseline|baseline|compat|compatibility|webm_vp9|vp9|webm|mpeg_mci|mpeg|mpg|mci|mpeg2_mpg|mpeg2|dvd)
      printf '%s\n' "$mode"
      return 0
      ;;
  esac

  if [[ $HAS_KDIALOG -eq 1 ]]; then
    mode="$(kdialog --menu "选择转码策略" \
      recommended "使用扫描推荐：MPG 用旧 MPEG，其余易出问题文件用 H.264 高质量" \
      h264_quality "H.264/AAC 高质量：CRF 18，兼容性好，体积较大" \
      h264_balanced "H.264/AAC 均衡：CRF 22，速度/体积/画质折中" \
      h264_fast "H.264/AAC 快速：CRF 20，速度优先，文件可能更大" \
      h264_small "H.264/AAC 小体积：CRF 27，节省空间但画质下降" \
      h264_baseline "H.264 Baseline：更保守的旧解码器兼容模式" \
      webm_vp9 "WebM VP9/Opus：少数游戏可绕过彩条，但兼容性不如 H.264" \
      mpeg_mci "旧 MPG/MCI：真 MPEG-1/MP2，适合旧 .mpg/.mpeg" \
      mpeg2_mpg "MPEG-2/MP2：DVD-era MPG 兼容备用" \
      2>/dev/null || true)"
  elif [[ $HAS_ZENITY -eq 1 ]]; then
    mode="$(zenity --list --title="选择转码策略" --column="策略" --column="说明" \
      recommended "使用扫描推荐：每个文件按规则选择" \
      h264_quality "H.264/AAC 高质量，CRF 18" \
      h264_balanced "H.264/AAC 均衡，CRF 22" \
      h264_fast "H.264/AAC 快速，CRF 20 + veryfast" \
      h264_small "H.264/AAC 小体积，CRF 27" \
      h264_baseline "H.264 Baseline，旧解码器兼容" \
      webm_vp9 "WebM VP9/Opus 绕过模式" \
      mpeg_mci "真 MPEG-1/MP2，旧 MPG/MCI" \
      mpeg2_mpg "真 MPEG-2/MP2，DVD-era MPG" \
      --height=400 --width=860 2>/dev/null || true)"
  else
    printf '\n选择转码策略：\n' >&2
    printf '1) 使用扫描推荐（默认）\n' >&2
    printf '2) H.264/AAC 高质量：CRF 18，兼容性好，体积较大\n' >&2
    printf '3) H.264/AAC 均衡：CRF 22，折中\n' >&2
    printf '4) H.264/AAC 快速：CRF 20 + veryfast，速度优先\n' >&2
    printf '5) H.264/AAC 小体积：CRF 27，节省空间\n' >&2
    printf '6) H.264 Baseline：旧解码器兼容\n' >&2
    printf '7) WebM VP9/Opus：绕过模式，兼容性不如 H.264\n' >&2
    printf '8) 旧 MPG/MCI：MPEG-1/MP2，适合旧 .mpg/.mpeg\n' >&2
    printf '9) MPEG-2/MP2：DVD-era MPG 备用\n' >&2
    printf '选择 [1-9]: ' >&2
    read -r n
    case "$n" in
      2) mode="h264_quality" ;;
      3) mode="h264_balanced" ;;
      4) mode="h264_fast" ;;
      5) mode="h264_small" ;;
      6) mode="h264_baseline" ;;
      7) mode="webm_vp9" ;;
      8) mode="mpeg_mci" ;;
      9) mode="mpeg2_mpg" ;;
      *) mode="recommended" ;;
    esac
  fi

  [[ -n "$mode" ]] || return 1
  normalize_transcode_mode "$mode"
}

normalize_backup_after_success() {
  case "${1:-ask}" in
    keep|保留) echo "keep" ;;
    delete|remove|rm|删|删除) echo "delete" ;;
    ask|auto|"") echo "ask" ;;
    *) echo "ask" ;;
  esac
}

maybe_offer_delete_backup() {
  local root="$1"
  local backup_dir="$root/$BACKUP_DIR_NAME"
  local mode
  mode="$(normalize_backup_after_success "$PVF_BACKUP_AFTER_SUCCESS")"

  [[ -d "$backup_dir/files" ]] || return 0

  case "$mode" in
    keep)
      ui_info "处理完成。\n\n备份、manifest 和日志位于：\n$backup_dir"
      return 0
      ;;
    delete)
      rm -rf -- "$backup_dir/files" "$backup_dir/$MANIFEST_NAME"
      ui_info "处理完成。\n\n已按 PVF_BACKUP_AFTER_SUCCESS=delete 删除备份文件。\n日志仍位于：\n$backup_dir"
      return 0
      ;;
  esac

  if ui_yesno "处理完成且没有失败。\n\n是否删除备份文件以节省空间？\n\n建议：确认游戏内视频正常播放后再删除。\n\n备份位置：\n$backup_dir"; then
    rm -rf -- "$backup_dir/files" "$backup_dir/$MANIFEST_NAME"
    ui_info "已删除备份文件。\n\n日志仍位于：\n$backup_dir"
  else
    ui_info "已保留备份。\n\n可之后在工具里使用“从备份还原”。\n备份位置：\n$backup_dir"
  fi
}

b64() {
  printf '%s' "$1" | base64 -w0
}

b64d() {
  printf '%s' "$1" | base64 -d
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_candidate_extension() {
  case "$1" in
    wmv|asf|wm|mpg|mpeg|m1v|m2v|vob|avi|mov|qt) return 0 ;;
    *) return 1 ;;
  esac
}

is_excluded_extension() {
  case "$1" in
    bik|bk2|smk|usm|cpk|acb|awb|pac) return 0 ;;
    *) return 1 ;;
  esac
}

is_high_risk_video_codec() {
  case "$1" in
    wmv1|wmv2|wmv3|vc1|mpeg1video|mpeg2video|msvideo1|msrle|msmpeg4v1|msmpeg4v2|msmpeg4v3|cvid|cinepak|indeo2|indeo3|indeo4|indeo5|svq1|svq3|qtrle|rpza) return 0 ;;
    *) return 1 ;;
  esac
}

is_high_risk_audio_codec() {
  case "$1" in
    wmav1|wmav2|wmapro|wmavoice|mp1|mp2) return 0 ;;
    *) return 1 ;;
  esac
}

ffprobe_value() {
  local file="$1"
  local args="$2"
  "$FFPROBE" -v error $args -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | head -n 1 | tr -d '\r'
}

media_info_line() {
  local file="$1"
  local format vcodec acodec width height duration
  format="$(ffprobe_value "$file" "-show_entries format=format_name")"
  vcodec="$(ffprobe_value "$file" "-select_streams v:0 -show_entries stream=codec_name")"
  acodec="$(ffprobe_value "$file" "-select_streams a:0 -show_entries stream=codec_name")"
  width="$(ffprobe_value "$file" "-select_streams v:0 -show_entries stream=width")"
  height="$(ffprobe_value "$file" "-select_streams v:0 -show_entries stream=height")"
  duration="$(ffprobe_value "$file" "-show_entries format=duration")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$format" "$vcodec" "$acodec" "$width" "$height" "$duration"
}

suggest_preset() {
  local ext="$1"
  local format="$2"
  local vcodec="$3"
  case "$ext" in
    mpg|mpeg|m1v|m2v|vob) echo "mpeg_mci"; return ;;
  esac
  case "$vcodec" in
    mpeg1video|mpeg2video) echo "mpeg_mci"; return ;;
  esac
  case "$format" in
    *mpeg*) echo "mpeg_mci"; return ;;
  esac
  echo "h264_quality"
}

risk_level() {
  local ext="$1"
  local format="$2"
  local vcodec="$3"
  local acodec="$4"

  case "$ext" in
    wmv|asf|wm|mpg|mpeg|m1v|m2v|vob) echo "high"; return ;;
  esac
  case "$format" in
    asf|*asf*|mpeg|*mpeg*) echo "high"; return ;;
  esac
  if is_high_risk_video_codec "$vcodec" || is_high_risk_audio_codec "$acodec"; then
    echo "high"; return
  fi

  case "$ext" in
    avi|mov|qt) echo "medium" ;;
    *) echo "low" ;;
  esac
}

scan_folder() {
  local root="$1"
  local report_file="$2"
  local queue_file="$3"
  local backup_dir="$root/$BACKUP_DIR_NAME"
  local high_count=0 medium_count=0 skipped_count=0 scanned_count=0

  : > "$report_file"
  : > "$queue_file"

  {
    echo "Deck Video Fixer $TOOL_VERSION"
    echo "Root: $root"
    echo ""
    echo "扫描规则：只自动处理旧 Windows/旧日系 PC 游戏常见易出问题的商业/专有视频格式。"
    echo "默认目标：WMV/ASF/WMA、MPG/MPEG、旧 AVI codec、旧 MOV/QuickTime codec。"
    echo "默认跳过：Bink/CRI/打包资源，以及现代正常 MP4/WebM/OGV。"
    echo ""
    printf '%-6s | %-9s | %-14s | %-14s | %-9s | %s\n' "判断" "建议" "视频" "音频" "容器" "路径"
    printf '%s\n' "----------------------------------------------------------------------------------------------------"
  } >> "$report_file"

  while IFS= read -r -d '' file; do
    local rel ext info format vcodec acodec width height duration risk preset
    rel="${file#"$root"/}"
    ext="$(lower "${file##*.}")"

    if is_excluded_extension "$ext"; then
      skipped_count=$((skipped_count + 1))
      continue
    fi
    if ! is_candidate_extension "$ext"; then
      continue
    fi

    scanned_count=$((scanned_count + 1))
    info="$(media_info_line "$file")"
    IFS=$'\t' read -r format vcodec acodec width height duration <<< "$info"
    format="$(lower "$format")"
    vcodec="$(lower "$vcodec")"
    acodec="$(lower "$acodec")"

    if [[ -z "$vcodec" ]]; then
      skipped_count=$((skipped_count + 1))
      continue
    fi

    risk="$(risk_level "$ext" "$format" "$vcodec" "$acodec")"
    preset="$(suggest_preset "$ext" "$format" "$vcodec")"

    case "$risk" in
      high)
        high_count=$((high_count + 1))
        printf '%-6s | %-9s | %-14s | %-14s | %-9s | %s\n' "处理" "$preset" "$vcodec" "${acodec:-none}" "${format:0:9}" "$rel" >> "$report_file"
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(b64 "$file")" "$(b64 "$rel")" "$preset" "$format" "$vcodec" "$acodec" >> "$queue_file"
        ;;
      medium)
        medium_count=$((medium_count + 1))
        printf '%-6s | %-9s | %-14s | %-14s | %-9s | %s\n' "可疑" "不默认" "$vcodec" "${acodec:-none}" "${format:0:9}" "$rel" >> "$report_file"
        ;;
    esac
  done < <(find "$root" \( -path "$backup_dir" -o -path "$backup_dir/*" \) -prune -o -type f -print0)

  {
    echo ""
    echo "统计：候选文件 $scanned_count 个；默认处理 $high_count 个；可疑 $medium_count 个；跳过 $skipped_count 个。"
    echo ""
    echo "输出策略说明："
    echo "  recommended   = 扫描器给每个易出问题文件建议 preset。"
    echo "  h264_quality  = H.264/AAC 高质量，CRF 18，兼容性好，体积较大。"
    echo "  h264_balanced = H.264/AAC 均衡，CRF 22，速度/体积/画质折中。"
    echo "  h264_fast     = H.264/AAC 快速，CRF 20 + veryfast，速度优先。"
    echo "  h264_small    = H.264/AAC 小体积，CRF 27，节省空间但画质下降。"
    echo "  h264_baseline = H.264 Baseline，适合更保守的旧解码器兼容需求。"
    echo "  webm_vp9      = WebM VP9/Opus 绕过模式，兼容性不如 H.264。"
    echo "  mpeg_mci      = 真 MPEG-1 Video + MP2 Audio + MPEG 容器，适合旧 .mpg/.mpeg。"
    echo "  mpeg2_mpg     = 真 MPEG-2 Video + MP2 Audio + MPEG 容器，DVD-era MPG 备用。"
    echo "  开始转码前会让你选择：使用推荐，或强制所有文件使用某个 preset。"
    echo ""
    echo "备份位置：$backup_dir"
  } >> "$report_file"

  printf '%s\n' "$high_count"
}

ensure_tools() {
  if [[ -z "$FFMPEG" || -z "$FFPROBE" ]]; then
    ui_error $'找不到 ffmpeg/ffprobe。\n\n本版本需要 ffmpeg 和 ffprobe。\n可以把静态 ffmpeg/ffprobe 放到脚本旁边的 bin/ 目录，或使用系统已有版本。'
    return 1
  fi
  return 0
}

write_manifest_header_if_needed() {
  local manifest="$1"
  if [[ ! -f "$manifest" ]]; then
    {
      echo "# Deck Video Fixer manifest v1"
      echo "# tool_version=$TOOL_VERSION"
      echo "# Fields: rel_b64 backup_rel_b64 original_sha256 format vcodec acodec preset converted_at"
    } > "$manifest"
  fi
}

convert_one() {
  local root="$1"
  local file="$2"
  local rel="$3"
  local preset="$4"
  local format="$5"
  local vcodec="$6"
  local acodec="$7"
  local backup_dir="$root/$BACKUP_DIR_NAME"
  local backup_file="$backup_dir/files/$rel"
  local manifest="$backup_dir/$MANIFEST_NAME"
  local tmp sha converted_at backup_rel

  if [[ -f "$backup_file" ]]; then
    printf '跳过：已经有备份，避免重复转码：%s\n' "$rel"
    return 0
  fi

  mkdir -p "$(dirname "$backup_file")"
  cp -p -- "$file" "$backup_file"
  sha="$(sha256sum "$backup_file" | awk '{print $1}')"

  case "$preset" in
    mpeg_mci)
      tmp="$(mktemp --tmpdir="$(dirname "$file")" ".pvf.XXXXXX.mpg")"
      "$FFMPEG" -hide_banner -nostdin -y -i "$file" \
        -map 0:v:0 -map 0:a? -sn -dn \
        -c:v mpeg1video -q:v 2 -pix_fmt yuv420p \
        -c:a mp2 -b:a 192k \
        -f mpeg "$tmp"
      ;;
    mpeg2_mpg)
      tmp="$(mktemp --tmpdir="$(dirname "$file")" ".pvf.XXXXXX.mpg")"
      "$FFMPEG" -hide_banner -nostdin -y -i "$file"         -map 0:v:0 -map 0:a? -sn -dn         -c:v mpeg2video -q:v 3 -pix_fmt yuv420p         -c:a mp2 -b:a 192k         -f mpeg "$tmp"
      ;;
    h264_balanced)
      tmp="$(mktemp --tmpdir="$(dirname "$file")" ".pvf.XXXXXX.mp4")"
      "$FFMPEG" -hide_banner -nostdin -y -i "$file" \
        -map 0:v:0 -map 0:a? -sn -dn \
        -c:v libx264 -pix_fmt yuv420p -preset fast -crf 22 -movflags +faststart \
        -c:a aac -b:a 160k \
        "$tmp"
      ;;
    h264_small)
      tmp="$(mktemp --tmpdir="$(dirname "$file")" ".pvf.XXXXXX.mp4")"
      "$FFMPEG" -hide_banner -nostdin -y -i "$file" \
        -map 0:v:0 -map 0:a? -sn -dn \
        -c:v libx264 -pix_fmt yuv420p -preset fast -crf 27 -movflags +faststart \
        -c:a aac -b:a 128k \
        "$tmp"
      ;;
    h264_baseline)
      tmp="$(mktemp --tmpdir="$(dirname "$file")" ".pvf.XXXXXX.mp4")"
      "$FFMPEG" -hide_banner -nostdin -y -i "$file" \
        -map 0:v:0 -map 0:a? -sn -dn \
        -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.1 -preset medium -crf 20 -movflags +faststart \
        -c:a aac -b:a 160k \
        "$tmp"
      ;;
    webm_vp9)
      tmp="$(mktemp --tmpdir="$(dirname "$file")" ".pvf.XXXXXX.webm")"
      "$FFMPEG" -hide_banner -nostdin -y -i "$file" \
        -map 0:v:0 -map 0:a? -sn -dn \
        -c:v libvpx-vp9 -crf 32 -b:v 0 -row-mt 1 \
        -c:a libopus -b:a 160k \
        "$tmp"
      ;;
    h264_quality|modern|*)
      tmp="$(mktemp --tmpdir="$(dirname "$file")" ".pvf.XXXXXX.mp4")"
      "$FFMPEG" -hide_banner -nostdin -y -i "$file" \
        -map 0:v:0 -map 0:a? -sn -dn \
        -c:v libx264 -pix_fmt yuv420p -preset medium -crf 18 -movflags +faststart \
        -c:a aac -b:a 192k \
        "$tmp"
      ;;
  esac

  if [[ ! -s "$tmp" ]]; then
    rm -f -- "$tmp"
    printf '失败：输出为空：%s\n' "$rel" >&2
    return 1
  fi
  if ! "$FFPROBE" -v error "$tmp" >/dev/null 2>&1; then
    rm -f -- "$tmp"
    printf '失败：ffprobe 无法读取输出：%s\n' "$rel" >&2
    return 1
  fi

  chmod --reference="$backup_file" "$tmp" 2>/dev/null || true
  touch --reference="$backup_file" "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$file"

  write_manifest_header_if_needed "$manifest"
  converted_at="$(date -Iseconds)"
  backup_rel="${backup_file#"$root"/}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(b64 "$rel")" "$(b64 "$backup_rel")" "$sha" "$format" "$vcodec" "$acodec" "$preset" "$converted_at" >> "$manifest"

  printf '完成：%s [%s]\n' "$rel" "$preset"
}

run_convert() {
  ensure_tools || return 1
  local root report queue high_count backup_dir log_file total done_count errors transcode_mode transcode_label
  root="$(choose_directory)" || return 0
  backup_dir="$root/$BACKUP_DIR_NAME"
  mkdir -p "$backup_dir"
  report="$(mktemp)"
  queue="$(mktemp)"
  log_file="$backup_dir/last-run.log"

  high_count="$(scan_folder "$root" "$report" "$queue")"
  ui_textbox "扫描结果" "$report"

  if [[ "$high_count" -eq 0 ]]; then
    ui_info $'没有找到默认需要处理的 Proton 兼容性问题视频。

可疑项目如果存在，会显示在扫描报告里，但本脚本不会默认处理。'
    rm -f "$report" "$queue"
    return 0
  fi

  transcode_mode="$(choose_transcode_mode)" || {
    rm -f "$report" "$queue"
    return 0
  }
  transcode_label="$(transcode_mode_label "$transcode_mode")"

  local msg
  msg="$(printf '找到 %s 个 Proton 兼容性问题视频。

转码策略：
%s

是否现在备份并转码这些文件？

原文件会保存到：
%s' "$high_count" "$transcode_label" "$backup_dir")"
  if ! ui_yesno "$msg"; then
    rm -f "$report" "$queue"
    return 0
  fi

  total="$high_count"
  done_count=0
  errors=0
  : > "$log_file"
  {
    echo "Deck Video Fixer $TOOL_VERSION"
    echo "Root: $root"
    echo "Started: $(date -Iseconds)"
    echo "ffmpeg: $FFMPEG"
    echo "ffprobe: $FFPROBE"
    echo "transcode_mode: $transcode_mode"
    echo "transcode_mode_label: $transcode_label"
    echo ""
  } >> "$log_file"

  while IFS=$'\t' read -r file_b64 rel_b64 preset format vcodec acodec; do
    local file rel
    file="$(b64d "$file_b64")"
    rel="$(b64d "$rel_b64")"
    case "$transcode_mode" in
      h264_quality|h264_balanced|h264_fast|h264_small|h264_baseline|webm_vp9|mpeg_mci|mpeg2_mpg) preset="$transcode_mode" ;;
      recommended|*) true ;;
    esac
    done_count=$((done_count + 1))
    printf '[%s/%s] %s [%s]\n' "$done_count" "$total" "$rel" "$preset" | tee -a "$log_file"
    if convert_one "$root" "$file" "$rel" "$preset" "$format" "$vcodec" "$acodec" >> "$log_file" 2>&1; then
      true
    else
      errors=$((errors + 1))
    fi
  done < "$queue"

  {
    echo ""
    echo "Finished: $(date -Iseconds)"
    echo "Errors: $errors"
  } >> "$log_file"

  ui_textbox "转码日志" "$log_file"
  if [[ "$errors" -eq 0 ]]; then
    maybe_offer_delete_backup "$root"
  else
    ui_error "$(printf '处理完成，但有 %s 个文件失败。\n\n已保留备份以便还原。请查看日志：\n%s' "$errors" "$log_file")"
  fi

  rm -f "$report" "$queue"
}

run_restore() {
  local root backup_dir files_dir count log_file
  root="$(choose_directory)" || return 0
  backup_dir="$root/$BACKUP_DIR_NAME"
  files_dir="$backup_dir/files"
  log_file="$backup_dir/restore.log"

  if [[ ! -d "$files_dir" ]]; then
    ui_error "$(printf '没有找到备份目录：\n%s' "$files_dir")"
    return 1
  fi

  count="$(find "$files_dir" -type f | wc -l | tr -d ' ')"
  if [[ "$count" -eq 0 ]]; then
    ui_error "备份目录为空。"
    return 1
  fi

  local msg
  msg="$(printf '将从备份还原 %s 个文件到游戏目录。\n\n这会覆盖当前同名文件。是否继续？' "$count")"
  if ! ui_yesno "$msg"; then
    return 0
  fi

  : > "$log_file"
  while IFS= read -r -d '' backup_file; do
    local rel target
    rel="${backup_file#"$files_dir"/}"
    target="$root/$rel"
    mkdir -p "$(dirname "$target")"
    cp -p -- "$backup_file" "$target"
    printf '还原：%s\n' "$rel" >> "$log_file"
  done < <(find "$files_dir" -type f -print0)

  ui_textbox "还原日志" "$log_file"
  ui_info "还原完成。"
}

main() {
  local action
  if [[ $# -gt 0 && -z "$PVF_GAME_DIR" ]]; then
    PVF_GAME_DIR="$1"
  fi
  action="$(choose_action)"
  case "$action" in
    convert) run_convert ;;
    restore) run_restore ;;
    *) exit 0 ;;
  esac
}

main "$@"
