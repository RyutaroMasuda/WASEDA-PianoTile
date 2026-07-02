# pin_test.sdc  タイミング制約
# 50MHz クロック
create_clock -name clk -period 20.000 [get_ports {clk}]
derive_clock_uncertainty

# 入力スイッチ・出力LEDは非同期(目視確認用)なのでfalse path
set_false_path -from [get_ports {sw_in[*]}] -to *
set_false_path -from [get_ports {mode_sw[*]}] -to *
set_false_path -from [get_ports {rst_n}] -to *
set_false_path -from * -to [get_ports {m_r[*]}]
set_false_path -from * -to [get_ports {m_c[*]}]
set_false_path -from * -to [get_ports {m_c8g}]
set_false_path -from * -to [get_ports {seg[*]}]
set_false_path -from * -to [get_ports {dig[*]}]
set_false_path -from * -to [get_ports {p[*]}]
