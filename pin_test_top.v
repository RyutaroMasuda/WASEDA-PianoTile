// =============================================================
//  pin_test_top.v   ピンアサイン確認（電流対策・ネストループ版）
//
//  DE10-Nano + FPGAPiano シールド (sch_rev2)
//
//  ■ 動作の流れ
//    mode_swでどの表示を行うか直接選択する(時間では自動的に切り替わらない)。
//    状態0: 行×列スキャン
//       行0で列0→1→...→9、終わったら行1で列0→...→9、…行3まで(行3まで来たら行0に戻ってループ)
//    状態1: 桁×セグスキャン
//       桁0でセグa→b→...→g、終わったら桁1で同様、…桁3まで(桁3まで来たら桁0に戻ってループ)
//    状態2: プログレスバー
//       p[0]→p[1]→...→p[9]と1本ずつ(p[9]まで来たらp[0]に戻ってループ)
//
//  ■ モード切替スイッチ(mode_sw[2:0])  ※タクトスイッチ(押した瞬間だけHigh)
//    mode_sw[0]が立ち上がったら → 状態0(行×列)に切り替えて保持
//    mode_sw[1]が立ち上がったら → 状態1(桁×セグ)に切り替えて保持
//    mode_sw[2]が立ち上がったら → 状態2(バー)に切り替えて保持
//    スイッチを離してもstateは変わらず、次に別のスイッチが押されるまで
//    そのまま保持される。
//    ※ この割り当ては仮です。実際のスイッチ配置と異なる場合は、下の
//      mode_rise0/1/2 の割り当てを変更してください。
//    モードを切り替えた瞬間、表示中のインデックス(inner_idx/outer_idx)は
//    0にリセットされ、その状態の最初から表示し直されます。
//
//  ■ 極性（前回確認済みの値。光らなければここを反転）
//    行 m_r   : Active Low  (AL_ROW=1)
//    列 m_c   : Active High (AL_COL=0)
//    緑 m_c8g : Active High (AL_COL=0)
//    7セグ seg: Active Low  (AL_SEG=1)
//    桁 dig   : Active Low  (AL_DIG=1)
//    バー p   : Active High (AL_BAR=0)
//
//  ■ 追加機能（スイッチによる緑LED手動点灯）
//    sw_in[i] (i=0~3) が押されている間、行iの位置でm_c8gを点灯する。
//    通常表示(m_r/m_c)とスイッチ表示(m_c8g)はphaseによる高速な時分割で
//    互いに干渉せず独立して表示される。
// =============================================================

module pin_test_top #(
    parameter CLK_HZ  = 50_000_000,
    parameter AL_ROW  = 0, //行
    parameter AL_COL  = 0, //列
    parameter AL_SEG  = 0,
    parameter AL_DIG  = 0,
    parameter AL_BAR  = 0,
    parameter STEP_HZ = 5            // 1ステップ(1本点灯)の切り替え速度。5なら0.2秒ごと
)(
    input  wire        clk,
    input  wire        rst_n,        // 未配線でも動くよう未使用扱い
    input  wire [3:0]  sw_in,        // スイッチ4個分。押下中はLow→Highどちらかは実機に応じて要確認
    input  wire [2:0]  mode_sw,      // モード切替スイッチ

    output wire [3:0]  m_r,
    output wire [9:0]  m_c,
    output wire        m_c8g,
    output wire [6:0]  seg,
    output wire [3:0]  dig,
    output wire [9:0]  p
);

    localparam STEP_TICKS = CLK_HZ / STEP_HZ;

    // ---- 大状態: 0=行×列, 1=桁×セグ, 2=バー ----
    localparam ST_ROWCOL = 2'd0;
    localparam ST_DIGSEG = 2'd1;
    localparam ST_BAR    = 2'd2;

    reg [1:0]  state     = ST_ROWCOL;
    reg [31:0] step_cnt  = 0;
    reg [3:0]  outer_idx = 0;        // 行 or 桁（外側ループ）
    reg [3:0]  inner_idx = 0;        // 列 or セグ or バー（内側ループ）

    // 各状態でのループ上限（0始まりなので「9」なら10回まわる）
    localparam OUTER_MAX_ROWCOL = 3; // 行0~3
    localparam INNER_MAX_ROWCOL = 9; // 列0~9
    localparam OUTER_MAX_DIGSEG = 3; // 桁0~3
    localparam INNER_MAX_DIGSEG = 6; // セグ a~g (0~6)
    localparam INNER_MAX_BAR    = 9; // バー0~9

    // ---- モード切替スイッチ(タクトスイッチ)によるstate選択 ----
    // タクトスイッチは押している間だけHighになり、離すとLowに戻るため、
    // レベル(今Highかどうか)で判定するとスイッチを離した瞬間にstateが
    // 元に戻ってしまう。そこで「押された瞬間(立ち上がりエッジ)」だけを
    // 検出し、そのときだけstateを更新する。スイッチを離してもstateは
    // そのまま保持され、次に別のスイッチが押されるまで変わらない。
    //
    // mode_sw[0]→ST_ROWCOL, mode_sw[1]→ST_DIGSEG, mode_sw[2]→ST_BAR
    // (仮の割り当て。実際のスイッチ配置に合わせて変更してください)
    reg [2:0] mode_sw_prev = 3'b000;
    always @(posedge clk) mode_sw_prev <= mode_sw;

    wire mode_rise0 = mode_sw[0] & ~mode_sw_prev[0];  // mode_sw[0]の立ち上がり
    wire mode_rise1 = mode_sw[1] & ~mode_sw_prev[1];  // mode_sw[1]の立ち上がり
    wire mode_rise2 = mode_sw[2] & ~mode_sw_prev[2];  // mode_sw[2]の立ち上がり

    // ---- スイッチ手動点灯用：高速ダイナミック点灯カウンタ(行スキャン版) ----
    // 行(m_r)を0~3まで1本ずつ高速に切り替える(本来のマトリクス駆動方式)。
    // 複数行を同時にONにしないことで、行をまたいだゴースト点灯を防ぐ。
    // DYN_DIVクロックごとに1行進む。50MHz/2000=25kHzで行が切り替わり、
    // 4行一周で約6.25kHzのリフレッシュ周波数(ちらつきは知覚されない速さ)。
    localparam DYN_DIV = 2000;
    reg [15:0] dyn_sub = 0; //行を切り替えるタイミングを数えるためのカウンタ（レジスタ）
    reg [1:0]  dyn_row = 0; //行番号
    always @(posedge clk) begin
        if (dyn_sub >= DYN_DIV - 1) begin
            dyn_sub <= 0;
            dyn_row <= dyn_row + 1;  // 2bit幅なので0→1→2→3→0と自然にラップ
        end else begin
            dyn_sub <= dyn_sub + 1;
        end
    end

    // ---- 表示フェーズ：通常表示とスイッチ表示を高速に時分割 ----
    // m_r(行)は通常表示とスイッチ機能の両方が共有している1本のバスなので、
    // 同時に別の値を出すことはできない(電気的に不可能)。そこで高速に
    // phaseを切り替えて、「通常表示の番」と「スイッチ表示の番」を時間で
    // 分け合う。十分速く切り替えれば、人の目には両方が同時に表示されて
    // いるように(残像効果で)見える。
    // PHASE_DIVクロックごとにphaseが反転。
    localparam PHASE_DIV = 20000;
    reg [15:0] phase_sub = 0;
    reg        phase     = 0;  // 0=通常表示の番, 1=スイッチ表示の番
    always @(posedge clk) begin
        if (phase_sub >= PHASE_DIV - 1) begin
            phase_sub <= 0;
            phase     <= ~phase;
        end else begin
            phase_sub <= phase_sub + 1;
        end
    end

    // ---- タイマー＋状態選択・インデックス更新 ----
    // stateはmode_swの立ち上がりエッジが来たときだけ更新され、それ以外は
    // 保持される。各状態の中ではinner_idx/outer_idxが0~maxを繰り返しループ
    // する(maxまで行ったら0に戻ってその状態内で循環し続ける)。
    // モードが切り替わった瞬間は、表示をその状態の最初からやり直すため、
    // カウンタを0にリセットする。
    always @(posedge clk) begin
        if (mode_rise0) begin
            state <= ST_ROWCOL;
        end else if (mode_rise1) begin
            state <= ST_DIGSEG;
        end else if (mode_rise2) begin
            state <= ST_BAR;
        end
        // どの立ち上がりも無ければstateはそのまま保持(何もしない)

        if (mode_rise0 || mode_rise1 || mode_rise2) begin
            // モード切替直後：カウンタをリセットして最初から表示し直す
            step_cnt  <= 0;
            inner_idx <= 0;
            outer_idx <= 0;
        end else if (step_cnt >= STEP_TICKS - 1) begin
            step_cnt <= 0;

            case (state)

            // 行×列: 内側(列)を1つ進める。列が上限まで行ったら
            // 内側を0に戻して外側(行)を1つ進める。行も上限まで行ったら
            // 外側も0に戻る(同じ状態内でループし続ける)。
            ST_ROWCOL: begin
                if (inner_idx >= INNER_MAX_ROWCOL) begin
                    inner_idx <= 0;
                    if (outer_idx >= OUTER_MAX_ROWCOL) begin
                        outer_idx <= 0;
                    end else begin
                        outer_idx <= outer_idx + 1;
                    end
                end else begin
                    inner_idx <= inner_idx + 1;
                end
            end

            // 桁×セグ: 上と同じ考え方
            ST_DIGSEG: begin
                if (inner_idx >= INNER_MAX_DIGSEG) begin
                    inner_idx <= 0;
                    if (outer_idx >= OUTER_MAX_DIGSEG) begin
                        outer_idx <= 0;
                    end else begin
                        outer_idx <= outer_idx + 1;
                    end
                end else begin
                    inner_idx <= inner_idx + 1;
                end
            end

            // バー: 外側ループは無く、内側だけ0~9を1周したら0に戻ってループ
            ST_BAR: begin
                if (inner_idx >= INNER_MAX_BAR) begin
                    inner_idx <= 0;
                end else begin
                    inner_idx <= inner_idx + 1;
                end
            end

            endcase

        end else begin
            step_cnt <= step_cnt + 1;
        end
    end

    // ---- 正論理(1=点灯)で組み立て ----
    reg [3:0]  r_mr;
    reg [9:0]  r_mc;
    reg        r_mc8g;
    reg [6:0]  r_seg;
    reg [3:0]  r_dig;
    reg [9:0]  r_p;

    always @(*) begin
        r_mr=0; r_mc=0; r_mc8g=0; r_seg=0; r_dig=0; r_p=0;

        case (state)

        ST_ROWCOL: begin
            // 通常表示は phase==0(通常表示の番)のときだけ出す。
            // phase==1のときは出さない(=m_rを0のままにする)ことで、
            // スイッチ側に行(m_r)の使用権を譲る。
            if (phase == 1'b0) begin
                r_mr = (4'b0001 << outer_idx[1:0]);  // 行: outer_idxで選んだ1本だけ立てる
                r_mc = (10'b1   << inner_idx[3:0]);  // 列: inner_idxで選んだ1本だけ立てる
            end
        end

        ST_DIGSEG: begin
            r_dig = (4'b0001 << outer_idx[1:0]); // 桁: outer_idxで選んだ1本だけ立てる
            r_seg = (7'b1    << inner_idx[2:0]); // セグ: inner_idxで選んだ1本だけ立てる
        end

        ST_BAR: begin
            r_p = (10'b1 << inner_idx[3:0]);     // バー: inner_idxで選んだ1本だけ立てる
        end

        endcase

        // ---- スイッチによる緑LED(m_c8g)の手動点灯：行ダイナミック点灯版 ----
        // 仮定: sw_in[0]→行0, sw_in[1]→行1, sw_in[2]→行2, sw_in[3]→行3
        //
        // phase==1(スイッチ表示の番)のときだけ動作する。これにより、
        // phase==0で出している通常表示(m_r/m_c)を上書きしてしまうことが
        // なくなり、m_cとm_c8gは見た目上、互いに干渉せず独立して表示される。
        //
        // m_r[0]~m_r[3]を1本ずつ高速に巡回させ(dyn_row)、常に1行だけが
        // ONになるようにする(複数行を同時にONにしない＝ゴースト点灯対策)。
        if (phase == 1'b1 && sw_in != 4'b0000) begin
            case (dyn_row)

            2'd0: begin
                r_mr = 4'b0001;          // 行0だけON
                if (sw_in[0]) r_mc8g = 1'b1;
            end

            2'd1: begin
                r_mr = 4'b0010;          // 行1だけON
                if (sw_in[1]) r_mc8g = 1'b1;
            end

            2'd2: begin
                r_mr = 4'b0100;          // 行2だけON
                if (sw_in[2]) r_mc8g = 1'b1;
            end

            2'd3: begin
                r_mr = 4'b1000;          // 行3だけON
                if (sw_in[3]) r_mc8g = 1'b1;
            end

            endcase
        end
    end

    // ---- 極性変換 ----
    assign m_r   = AL_ROW ? ~r_mr   : r_mr;
    assign m_c   = AL_COL ? ~r_mc   : r_mc;
    assign m_c8g = AL_COL ? ~r_mc8g : r_mc8g;
    assign seg   = AL_SEG ? ~r_seg  : r_seg;
    assign dig   = AL_DIG ? ~r_dig  : r_dig;
    assign p     = AL_BAR ? ~r_p    : r_p;

endmodule