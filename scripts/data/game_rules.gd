class_name GameRules
## 全局规则常量。集中放这里，方便一处改动、全局生效。
##
## 本文件不依赖任何其他脚本，任何层都可以安全引用它。

## 格子边长（像素）。
## 【关键不变式】塔位格与路径格永不重叠（由 MapData.validate() 强制），
## 所以「塔位格中心 ↔ 相邻路径格中心」的最小距离恰好等于 TILE_SIZE。
const TILE_SIZE := 64

## 近战敌人射程上限。
## 【关键不变式】必须严格小于 TILE_SIZE，这样近战敌人永远够不到任何塔。
## 将来要加「能打到塔的远程敌人」，把它的 attack_range 调到 > TILE_SIZE 即可。
const MELEE_RANGE_MAX := 48.0

## 漏怪一次扣多少关卡血量。
## 当前设计：漏怪计数制，每漏一只扣 1 点（不区分兵种）。
## 将来要按兵种区分，改这里 + 给 EnemyData 加一个字段。
const LEAK_DAMAGE := 1
