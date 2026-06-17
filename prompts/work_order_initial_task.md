<注释>
后台工单 WorkOrderAgent 首轮 user message 模板。
保持“稳定项目索引在前、动态工单信息在后”，以利于 DeepSeek 前缀缓存。
</注释>

{{work_order_project_index}}

---

# 当前工单（动态尾部）

{{work_order_order_block}}

请执行上述工单。优先利用项目索引定位相关 KB、场景、变量、角色和资源；索引不是全文，缺少正文或完整 DSL 时再调用工具读取。
