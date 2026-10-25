-- Original project code. SPDX-License-Identifier: AGPL-3.0-or-later
-- Source baseline: koreader/koreader 9192014d8bd82a91dc1012473be0f238dedfdb54.
-- Backend-specific keys and event names stay in adapter.lua.
local R = {
    {id="font_gamma",title="对比度",section="reading",kind="number",min=0,max=56,step=1},
    {id="font_base_weight",title="字重",section="reading",kind="number",min=-3,max=5.5,step=.25,fractional=true},
    {id="word_spacing",title="词间距",section="reading",kind="pair",help="缩放10—500%，收缩25—100%。"},
    {id="word_expansion",title="字间距扩展",section="reading",kind="number",min=0,max=20,step=1,suffix="%"},
    {id="cjk_width_scaling",title="中日韩字符宽度",section="reading",kind="number",min=100,max=150,step=1,suffix="%"},
    { id="page_margins",title="页边距",section="reading",kind="margins",help="左、上、右、下四个边距，仅作用于当前书籍。" },
    { id = "embedded_css", title = "内嵌样式", section = "reading", kind = "toggle",
      help = "使用书籍自带的排版样式。只影响当前流式文档。" },
    { id = "embedded_fonts", title = "内嵌字体", section = "reading", kind = "toggle",
      help = "使用书籍内嵌的字体。需要启用内嵌样式，且书中确有内嵌字体。" },
    { id = "font_size", title = "字号", section = "reading", kind = "number", min = 12, max = 255, step = .5, fractional = true,
      help = "修改当前书籍字号。以 KOReader 的缩放单位显示。" },
    { id = "font_face", title = "阅读字体", section = "reading", kind = "choice",
      help = "从当前设备已安装字体中选择。只改变当前书籍。" },
    { id = "line_spacing", title = "行距", section = "reading", kind = "number", min = 50, max = 200, step = 5,
      help = "按百分比调整行距。书内样式可能影响视觉效果。", suffix = "%" },
    { id = "font_hinting", title = "字体微调", section = "reading", kind = "choice",
      choices = {{0, "关闭"}, {1, "字体原生"}, {2, "自动"}},
      help = "调整字体与像素网格的对齐方式。修改后重新排版。" },
    { id = "font_kerning", title = "字偶距", section = "reading", kind = "choice",
      choices = {{0, "关闭"}, {1, "快速"}, {2, "良好"}, {3, "最佳"}},
      help = "控制字形间距与连字处理。修改后重新排版。" },
    { id = "sort", title = "原生文件列表排序", section = "files", kind = "choice",
      help = "控制 KOReader 文件管理器的排序；与新书库排序分别管理。" },
    { id = "show_hidden", title = "显示隐藏文件", section = "files", kind = "toggle",
      help = "显示以点开头的文件与文件夹。只改变显示，不修改文件。" },
}
R.by_id = {}
for _, item in ipairs(R) do R.by_id[item.id] = item end
function R.items(section)
    local t = {}
    for _, item in ipairs(R) do if item.section == section then t[#t+1] = item end end
    return t
end
return R
