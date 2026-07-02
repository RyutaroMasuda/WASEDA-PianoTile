# 修正履歴（Fitterエラー対応）

## エラー: Can't place node "sw_in[3]" -- illegal location PIN_AE18

### 原因
GPIO_1テーブルの読み取りミス。以下を修正:

| 信号 | 旧(誤) | 新(正) | GPIO_1 |
|------|--------|--------|--------|
| sw_in[1] | AE17 | **AE20** | [33] (J2 pin38) |
| sw_in[3] | AE18 | **AE17** | [35] (J2 pin40) |
| rst_n    | AH16 | **AH17** | 内蔵KEY0 |

AE18 はDE10-Nanoに存在しない（または別バンク）ピンだったため
Fitterが配置できずエラーになっていた。

## 極性の確定（重要）
回路図の追加確認で、行(m_r)・列ドライバ・7セグすべてが
PチャネルMOSFET(IRLML2246)のハイサイド駆動と判明。
→ ゲートをLowに引くと点灯（Active Low）。

pin_test_top.v に ACTIVE_LOW パラメータを追加（デフォルト=1）。
内部は正論理(1=点灯)で組み、出力直前で反転している。

### 実機で極性が合わない場合
- 全点灯モード(00)で何も光らない → ACTIVE_LOW=0 に変更して再コンパイル
- 一部だけ光らない → そのグループだけ個別に極性を変える必要あり
  （その場合は該当するassign文のACTIVE_LOW分岐を手動調整）

---

# 修正2: m_c8g の幅エラー + 極性の確定

## エラー: Can't place multiple pins assigned to Pin_AE6
m_c8g[0..3] が4ビットとも同じ1ピンAE6に割当たろうとして衝突。

### 原因
m_c8g を [3:0] の4ビットにしていたが、回路図上は
**1本の信号**（DRV777ドライバICの1入力）。
行スキャンと時分割で4行分の緑を表示する設計のため、配線は1本。

### 修正
pin_test_top.v の m_c8g を `output wire m_c8g` （1ビット）に変更。

## 極性の最終確定（ドライバICから判明）
| グループ | ドライバ | 極性 | パラメータ |
|---------|---------|------|-----------|
| 行 m_r   | PチャネルFET(ハイサイド) | Active Low  | AL_ROW=1 |
| 列 m_c   | DRV777(シンク)          | Active High | AL_COL=0 |
| 緑 m_c8g | DRV777(シンク)          | Active High | AL_COL=0 |
| 7セグ seg | PチャネルFET            | Active Low  | AL_SEG=1 |
| 桁 dig   | (暫定)                  | Active Low  | AL_DIG=1 |
| バー p   | (暫定)                  | Active High | AL_BAR=0 |

★ 行と列で極性が逆。pin_test_top.v はグループごとに
  AL_xxx パラメータで極性を指定できる。

### 実機調整
mode 00(全点灯)で光らないグループがあれば、そのAL_xxxを反転:
- 行が光らない → AL_ROW を 0 に
- 列が光らない → AL_COL を 0→1 に（m_c8gも連動）
- 7セグが光らない → AL_SEG を 0 に
- 桁が出ない → AL_DIG を反転
- バーが光らない → AL_BAR を反転
