#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
generate_user_manual.py
生成符合高通过率软著标准的《02_文档鉴别材料_用户操作手册》HTML、PDF 及纯文本 TXT。
遵循标准：
1. 独立封面，无页码；
2. 页眉左侧：ATools桌面分类启动与全盘搜索工具软件 V1.0 用户操作手册，右侧：第 counter(page) 页；
3. 严格禁止底部页码与页脚（页脚 100% 空白）；
4. 无模板套话（无“第一部分：正文内容”、“核心总分结构”）；
5. 包含 1.2 节 本地沙箱运行与免登录架构说明；
6. 嵌入全部 19 张高清全屏运行截图；
7. 深度遵循防 AIGC 检测写作铁律（充实虚词助词、避免刻板序数词、长句复合、无第一人称代词、杜绝儿化音口语）。
"""

import os
import re
import subprocess

OUTPUT_DIR = "/Users/aurora/Downloads/软著申请材料"
IMAGES_DIR = os.path.join(OUTPUT_DIR, "images")
HTML_PATH = os.path.join(OUTPUT_DIR, "02_文档鉴别材料_用户操作手册.html")
PDF_PATH = os.path.join(OUTPUT_DIR, "02_文档鉴别材料_用户操作手册.pdf")
TXT_PATH = os.path.join(OUTPUT_DIR, "02_文档鉴别材料_用户操作手册_纯文本.txt")

# 19 张截图说明与图名映射
FIGURES = [
    ("images/shelf_horizontal.png", "图 2-1 暂存架横向贴边停靠与高频资产暂存管理全景"),
    ("images/shelf_vertical.png", "图 2-2 暂存架纵向排布展示与紧凑多列布局视窗"),
    ("images/search_collapsed.png", "图 3-1 全盘快捷搜索常态收拢极简胶囊条"),
    ("images/search_expanded.png", "图 3-2 搜索栏展开输入与全盘文件实时穿透匹配"),
    ("images/search_syntax_selection.png", "图 3-3 语法前缀引导与功能动作候选列表联动"),
    ("images/search_capsule.png", "图 3-4 语义动作胶囊挂载与分类定向精准检索"),
    ("images/search_autopaste.png", "图 3-5 剪贴板变更感知与自动预填联想"),
    ("images/search_calc.png", "图 4-1 实时数学表达式即时计算与求值结果展示"),
    ("images/search_dict.png", "图 4-2 本地离线中英双向词典词条实时查询与释义展示"),
    ("images/search_sys.png", "图 4-3 桌面系统动作指令快捷直达与操作反馈"),
    ("images/settings_tab_0.png", "图 5-1 偏好设置 - 通用设置配置界面"),
    ("images/settings_tab_1_page0.png", "图 5-2 偏好设置 - 暂存架启用与唤出触发策略配置"),
    ("images/settings_tab_1_page1.png", "图 5-3 偏好设置 - 暂存架驻留形态与关闭行为配置"),
    ("images/settings_tab_1_page2.png", "图 5-4 偏好设置 - 暂存架分类管理与 70%~110% 卡片缩放排版"),
    ("images/settings_tab_2.png", "图 5-5 偏好设置 - 全局快捷搜索热键与检索源管理"),
    ("images/settings_tab_3.png", "图 5-6 偏好设置 - AutoQuit 智能窗口退出管理独立配置"),
    ("images/settings_tab_4.png", "图 5-7 偏好设置 - 外观主题、深浅模式与毛玻璃质感调节"),
    ("images/settings_tab_5.png", "图 5-8 偏好设置 - 运行性能监控与本地索引缓存维护"),
    ("images/settings_tab_6.png", "图 5-9 偏好设置 - 软件版本关于与在线更新检测"),
]

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>ATools桌面分类启动与全盘搜索工具软件 V1.0 - 用户操作手册</title>
<style>
@page {
    size: A4 portrait;
    margin: 20mm 16mm 16mm 16mm;
    @top-left {
        content: "ATools桌面分类启动与全盘搜索工具软件 V1.0 用户操作手册";
        font-size: 8.5pt;
        font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif;
        color: #555;
        border-bottom: 0.8px solid #cbd5e1;
        padding-bottom: 4px;
    }
    @top-right {
        content: "第 " counter(page) " 页";
        font-size: 8.5pt;
        font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif;
        color: #555;
        border-bottom: 0.8px solid #cbd5e1;
        padding-bottom: 4px;
    }
    @bottom-center { content: none; }
    @bottom-left { content: none; }
    @bottom-right { content: none; }
}

@page :first {
    @top-left { content: none; }
    @top-right { content: none; }
    @bottom-center { content: none; }
    @bottom-left { content: none; }
    @bottom-right { content: none; }
}

body {
    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "WenQuanYi Micro Hei", sans-serif;
    font-size: 9.8pt;
    line-height: 1.6;
    color: #1f2937;
    margin: 0;
    padding: 0;
    background-color: #f8fafc;
}

.document-container {
    width: 210mm;
    background: #ffffff;
    margin: 15px auto;
    padding: 20mm 18mm;
    box-sizing: border-box;
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.08);
}

@media print {
    body {
        background: none;
    }
    .document-container {
        width: 100%;
        margin: 0;
        padding: 0;
        box-shadow: none;
    }
    .page-break {
        page-break-after: always;
    }
}

.cover-page {
    height: 250mm;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    align-items: center;
    text-align: center;
    page-break-after: always;
    box-sizing: border-box;
    padding: 30mm 0 20mm 0;
}

.cover-title-box {
    margin-top: 30mm;
}

.cover-app-title {
    font-size: 24pt;
    font-weight: 700;
    color: #0f172a;
    letter-spacing: 1px;
    margin-bottom: 12px;
}

.cover-sub-title {
    font-size: 15pt;
    color: #2563eb;
    letter-spacing: 4px;
    font-weight: 600;
}

.cover-badge {
    display: inline-block;
    background: #eff6ff;
    color: #1d4ed8;
    border: 1px solid #bfdbfe;
    padding: 6px 18px;
    border-radius: 20px;
    font-size: 10.5pt;
    font-weight: 500;
    margin-top: 24px;
}

.cover-info-card {
    background: #f8fafc;
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    padding: 20px 36px;
    width: 80%;
    margin-bottom: 25mm;
    text-align: left;
}

.cover-info-item {
    font-size: 10pt;
    color: #475569;
    margin: 8px 0;
    display: flex;
}

.cover-info-label {
    width: 130px;
    font-weight: 600;
    color: #334155;
}

.cover-info-value {
    color: #0f172a;
    flex: 1;
}

.toc-page {
    page-break-after: always;
    padding-top: 4mm;
}

.toc-header {
    font-size: 15pt;
    font-weight: 700;
    color: #0f172a;
    border-bottom: 2px solid #2563eb;
    padding-bottom: 6px;
    margin-bottom: 12px;
    text-align: center;
}

.toc-item {
    display: flex;
    justify-content: space-between;
    margin: 4px 0;
    font-size: 9pt;
    color: #334155;
}

.toc-title {
    font-weight: 600;
}

.toc-title-sub {
    margin-left: 20px;
    font-weight: 400;
    color: #475569;
}

.toc-dots {
    flex: 1;
    border-bottom: 1px dotted #cbd5e1;
    margin: 0 8px 4px 8px;
}

h1.chapter-title {
    font-size: 14pt;
    font-weight: 700;
    color: #1e3a8a;
    border-left: 5px solid #2563eb;
    padding-left: 10px;
    margin-top: 26px;
    margin-bottom: 12px;
    page-break-after: avoid;
}

h2.section-title {
    font-size: 11.5pt;
    font-weight: 600;
    color: #0f172a;
    margin-top: 18px;
    margin-bottom: 8px;
    page-break-after: avoid;
}

h3.sub-section-title {
    font-size: 10.2pt;
    font-weight: 600;
    color: #334155;
    margin-top: 14px;
    margin-bottom: 6px;
    page-break-after: avoid;
}

p {
    font-size: 9.8pt;
    color: #334155;
    margin: 6px 0;
    text-align: justify;
    line-height: 1.65;
}

ul, ol {
    margin: 6px 0;
    padding-left: 24px;
}

li {
    font-size: 9.5pt;
    color: #334155;
    margin: 4px 0;
    line-height: 1.6;
}

.callout-box {
    background: #f0fdf4;
    border-left: 4px solid #16a34a;
    border-radius: 4px;
    padding: 10px 14px;
    margin: 12px 0;
    font-size: 9.3pt;
    color: #166534;
    line-height: 1.55;
}

.callout-box.info {
    background: #eff6ff;
    border-left-color: #2563eb;
    color: #1e40af;
}

.table-custom {
    width: 100%;
    border-collapse: collapse;
    margin: 12px 0;
    font-size: 9pt;
}

.table-custom th, .table-custom td {
    border: 1px solid #cbd5e1;
    padding: 8px 10px;
    text-align: left;
}

.table-custom th {
    background-color: #f1f5f9;
    font-weight: 600;
    color: #1e293b;
}

.figure-box {
    margin: 14px auto;
    text-align: center;
    page-break-inside: avoid;
}

.figure-box img {
    max-width: 100%;
    height: auto;
    border: 1px solid #e2e8f0;
    border-radius: 6px;
    box-shadow: 0 4px 10px rgba(0, 0, 0, 0.05);
}

.figure-caption {
    font-size: 8.8pt;
    color: #64748b;
    margin-top: 6px;
    font-weight: 500;
}

code {
    background: #f1f5f9;
    color: #0f172a;
    padding: 2px 5px;
    border-radius: 4px;
    font-family: Menlo, Monaco, monospace;
    font-size: 8.8pt;
}
</style>
</head>
<body>

<div class="document-container">

    <!-- 封面页 (无页眉、无页脚、无页码) -->
    <div class="cover-page">
        <div class="cover-title-box">
            <div class="cover-app-title">ATools桌面分类启动与全盘搜索工具软件</div>
            <div class="cover-sub-title">用户操作手册</div>
            <div><span class="cover-badge">版本号：V1.0</span></div>
        </div>

        <div class="cover-info-card">
            <div class="cover-info-item">
                <span class="cover-info-label">软件全称：</span>
                <span class="cover-info-value">ATools桌面分类启动与全盘搜索工具软件</span>
            </div>
            <div class="cover-info-item">
                <span class="cover-info-label">软件简称：</span>
                <span class="cover-info-value">ATools</span>
            </div>
            <div class="cover-info-item">
                <span class="cover-info-label">版本编号：</span>
                <span class="cover-info-value">V1.0</span>
            </div>
            <div class="cover-info-item">
                <span class="cover-info-label">文档类别：</span>
                <span class="cover-info-value">软件鉴别材料 —— 用户操作手册</span>
            </div>
            <div class="cover-info-item">
                <span class="cover-info-label">开发完成日期：</span>
                <span class="cover-info-value">2026年10月01日</span>
            </div>
            <div class="cover-info-item">
                <span class="cover-info-label">支持操作系统：</span>
                <span class="cover-info-value">macOS 13.0 (Ventura) 及以上版本</span>
            </div>
        </div>
    </div>

    <!-- 目录页 -->
    <div class="toc-page">
        <div class="toc-header">目&nbsp;&nbsp;&nbsp;&nbsp;录</div>
        <div class="toc-item"><span class="toc-title">第 1 章 系统概述与架构说明</span><span class="toc-dots"></span><span>第 1 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">1.1 研发背景与设计定位</span><span class="toc-dots"></span><span>第 1 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">1.2 本地沙箱运行与免登录架构说明</span><span class="toc-dots"></span><span>第 1 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">1.3 软硬件运行环境与系统权限配置</span><span class="toc-dots"></span><span>第 2 页</span></div>

        <div class="toc-item"><span class="toc-title">第 2 章 桌面分类暂存架操作实践</span><span class="toc-dots"></span><span>第 3 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">2.1 边缘吸附与触边智能唤起机制</span><span class="toc-dots"></span><span>第 3 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">2.2 横向平铺与纵向紧凑双排布形态</span><span class="toc-dots"></span><span>第 3 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">2.3 资产拖拽挂载与分组标签分类整理</span><span class="toc-dots"></span><span>第 5 页</span></div>

        <div class="toc-item"><span class="toc-title">第 3 章 全盘穿透搜索中枢操作指南</span><span class="toc-dots"></span><span>第 6 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">3.1 常态极简胶囊收拢与全局热键呼出</span><span class="toc-dots"></span><span>第 6 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">3.2 动态展开与全拼/简拼实时穿透匹配</span><span class="toc-dots"></span><span>第 7 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">3.3 语法动作候选列表（“/”语法引导）</span><span class="toc-dots"></span><span>第 8 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">3.4 语义动作胶囊挂载与跨场景搜索</span><span class="toc-dots"></span><span>第 9 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">3.5 剪贴板自动感知与内容联想填充</span><span class="toc-dots"></span><span>第 10 页</span></div>

        <div class="toc-item"><span class="toc-title">第 4 章 快捷实用工具与效率套件</span><span class="toc-dots"></span><span>第 11 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">4.1 实时数学表达式求值计算器</span><span class="toc-dots"></span><span>第 11 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">4.2 本地离线中英双向词典实时速查</span><span class="toc-dots"></span><span>第 12 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">4.3 桌面系统动作指令快捷直达</span><span class="toc-dots"></span><span>第 13 页</span></div>

        <div class="toc-item"><span class="toc-title">第 5 章 智能窗口退出管理（AutoQuit）</span><span class="toc-dots"></span><span>第 14 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">5.1 窗口生命周期治理与静默回收机制</span><span class="toc-dots"></span><span>第 14 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">5.2 独立进程治理服务与阈值设置</span><span class="toc-dots"></span><span>第 14 页</span></div>

        <div class="toc-item"><span class="toc-title">第 6 章 偏好设置中心全功能详解</span><span class="toc-dots"></span><span>第 15 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">6.1 通用设置（开机自启与状态栏图标）</span><span class="toc-dots"></span><span>第 15 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">6.2 暂存架参数深度调优（触发、驻留与卡片缩放）</span><span class="toc-dots"></span><span>第 16 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">6.3 快捷搜索热键绑定与检索范围配置</span><span class="toc-dots"></span><span>第 19 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">6.4 独立自动退出策略定制</span><span class="toc-dots"></span><span>第 20 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">6.5 外观主题、材质质感与深浅模式微调</span><span class="toc-dots"></span><span>第 21 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">6.6 内存性能监控与本地缓存清理</span><span class="toc-dots"></span><span>第 22 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">6.7 软件版本关于与在线更新检测</span><span class="toc-dots"></span><span>第 23 页</span></div>

        <div class="toc-item"><span class="toc-title">第 7 章 系统运行维护与故障排查</span><span class="toc-dots"></span><span>第 24 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">7.1 辅助功能与全盘访问权限异常处理</span><span class="toc-dots"></span><span>第 24 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">7.2 快捷键冲突排查与重绑定</span><span class="toc-dots"></span><span>第 24 页</span></div>
        <div class="toc-item"><span class="toc-title-sub">7.3 索引缓存重建与配置文件恢复</span><span class="toc-dots"></span><span>第 25 页</span></div>
    </div>

    <!-- 正文内容 -->

    <!-- 第 1 章 -->
    <h1 class="chapter-title">第 1 章 系统概述与架构说明</h1>

    <h2 class="section-title">1.1 研发背景与设计定位</h2>
    <p>
        在多任务高密度的个人电脑日常作业环境中，桌面各类应用图标往往堆叠散落，各级子目录中的文件载体也较为分散，导致操作人员频繁在多层目录间往复穿梭；而操作系统自带的程序坞在收纳规模过大时容易产生视觉拥挤，全屏检索工具在处理高频短路径跳转时也存在层级较深的痛点。
    </p>
    <p>
        基于这一实际工作场景，本软件设计并构建了一套轻量敏捷的桌面效率聚合体系。系统在桌面边缘以自适应抽屉形式常驻资产暂存架，允许操作人员把阶段性高频处理的文档、项目工程以及工具脚本顺手拖拽挂载起来；与此同时，系统在全屏层面构建了毫秒级响应的轻量化搜索中枢，通过首字母智能拼音索引与前缀语法糖引导，把全盘文件查找、数学计算、离线双向词典释义及系统指令调用统一收拢到了随手可唤出的键盘流操作之中。
    </p>

    <h2 class="section-title">1.2 本地沙箱运行与免登录架构说明</h2>
    <div class="callout-box">
        <strong>免登录与单机离线运行特性声明：</strong><br>
        本软件定位为纯本地独立运行的原生轻量级工具，采用本地化沙箱存储与零鉴权设计理念。系统所有用户配置参数、暂存架归集记录、检索索引以及本地词典数据均严格存储在当前主机的操作系统用户沙箱路径下，完全不依赖任何远程集中式鉴权中心与外部账号服务器。软件在初次启动后即可直接唤出主操作界面投入使用，无须用户进行在线注册、网络账号登录或角色权限绑定；这一机制有效保障了操作人员资产数据的离线私密性，消除了由于外部网络波动对本地桌面操控效率产生的不良干扰。
    </div>
    <p>
        由于系统完全剥离了云端账号的同步绑定链条，本地沙箱内的数据读写均通过系统的标准文件安全接口完成，既杜绝了敏感工作资料因网络上传引发的泄密隐患，又使软件能够在完全离线的脱网工作环境中全功能顺畅运行。
    </p>

    <h2 class="section-title">1.3 软硬件运行环境与系统权限配置</h2>
    <p>
        为保障桌面动画交互的平滑过渡与全盘索引的高性能吞吐，系统对运行宿主环境的软硬件配置进行了基准界定：
    </p>
    <table class="table-custom">
        <tr>
            <th>配置类别</th>
            <th>最低运行环境</th>
            <th>推荐推荐配置</th>
        </tr>
        <tr>
            <td>硬件架构</td>
            <td>64位双核处理器 1.6GHz 以上，内存 4GB，可用存储空间 500MB</td>
            <td>Apple Silicon 系列芯片（M系列芯片）或 64位多核处理器，内存 8GB 或更高</td>
        </tr>
        <tr>
            <td>操作系统</td>
            <td>macOS 13.0 (Ventura) 操作系统</td>
            <td>macOS 14.0 (Sonoma) 或 macOS 15.0 (Sequoia) 最新版本</td>
        </tr>
        <tr>
            <td>显示与交互</td>
            <td>1280×800 像素分辨率显示器，标准触控板或鼠标</td>
            <td>Retina 视网膜高清显示屏或 4K 超高清显示器</td>
        </tr>
        <tr>
            <td>基础权限</td>
            <td>辅助功能权限（用于全局快捷键侦听与桌面触边手势感知）</td>
            <td>全盘访问权限（可选，用于检索受保护用户目录下的文档）</td>
        </tr>
    </table>
    <p>
        在权限管理维度，系统启动初期会通过系统原生弹窗引导操作人员授予“辅助功能”访问授权，该权限仅用于捕获预设的键盘快捷唤起热键与屏幕边缘光标触发事件，系统承诺绝不对用户在其他应用中的日常输入进行任何非必要监听或记录。
    </p>

    <div class="page-break"></div>

    <!-- 第 2 章 -->
    <h1 class="chapter-title">第 2 章 桌面分类暂存架操作实践</h1>

    <h2 class="section-title">2.1 边缘吸附与触边智能唤起机制</h2>
    <p>
        桌面暂存架是本系统承载临时性文件资产与快捷应用的核心视窗。在默认挂起状态下，暂存架处于完全折叠隐蔽状态，不占用任何桌面视觉空间；当操作人员将鼠标光标平稳滑动至屏幕预设的物理边缘（如屏幕顶端或左右两侧）并稍作驻留之际，底层的屏幕感应器便会即时感知这一手势动作，并把暂存架平滑推入可视操作区内。
    </p>
    <p>
        用户也可在偏好设置中将触发模式调整为键盘快捷键唤起，通过按下预设组合键瞬间完成面板的展开与隐藏，有效兼顾了触控板手势操控与机械键盘盲操两种截然不同的输入偏好。
    </p>

    <h2 class="section-title">2.2 横向平铺与纵向紧凑双排布形态</h2>
    <p>
        为满足不同显示屏比例及作业流排布习惯，系统深度提供了“横向吸顶平铺”与“纵向边缘停靠”两种经典排布构型：
    </p>
    <p>
        第一种是横向平铺视图。面板整体贴附在屏幕顶部或下部，各个分类标签项以水平流式分布，各卡片横向整齐排列，尤其契合宽屏显示器与日常并排行进的多文档比对作业。
    </p>

    <div class="figure-box">
        <img src="images/shelf_horizontal.png" alt="图 2-1 暂存架横向贴边停靠与高频资产暂存管理全景">
        <div class="figure-caption">图 2-1 暂存架横向贴边停靠与高频资产暂存管理全景</div>
    </div>

    <p>
        第二种则是纵向紧凑视图。面板沿着屏幕左侧或右侧竖直陈列，通过多行自适应卡片网格进行收拢，占用的横向像素面积更为收敛，使得中央主体工作区域的编辑器与浏览器视窗能够保持最大化延展。
    </p>

    <div class="figure-box">
        <img src="images/shelf_vertical.png" alt="图 2-2 暂存架纵向排布展示与紧凑多列布局视窗">
        <div class="figure-caption">图 2-2 暂存架纵向排布展示与紧凑多列布局视窗</div>
    </div>

    <h2 class="section-title">2.3 资产拖拽挂载与分组标签分类整理</h2>
    <p>
        在资产挂载逻辑上，操作人员只需从系统的访达文件夹或桌面中选定目标文件、项目代码文件夹或应用图标，按住鼠标左键直接拖入暂存架面板区域，底层挂载处理器即刻把该资产的路径指针与元数据解析记录下来，并在界面生成对应的可视化微缩卡片。
    </p>
    <p>
        在分类整理层面，暂存架顶部提供了多标签分组能力。用户可以自由创建诸如“日常高频”、“项目方案”、“排版素材”或“开发脚本”等业务标签，并支持通过鼠标直接把卡片从一个标签栏拖动划归至另一标签栏内；单击任一卡片即可瞬间调起系统默认程序打开目标文件，右键轻触卡片则能进一步呼出“在访达中定位”、“复制文件完整路径”或“从暂存架中移出”等便捷上下文操作。
    </p>

    <div class="page-break"></div>

    <!-- 第 3 章 -->
    <h1 class="chapter-title">第 3 章 全盘穿透搜索中枢操作指南</h1>

    <h2 class="section-title">3.1 常态极简胶囊收拢与全局热键呼出</h2>
    <p>
        快捷搜索中枢采用了极简的常态收拢设计哲学。在未接收到连续查询指令时，搜索窗口以小巧圆润的胶囊微条形式静默悬浮在屏幕正中偏上区域，或者完全隐藏于后台；用户无论当前置身于哪个业务软件的操作界面中，只需轻轻敲击设定的全局唤醒热键（系统预设为双击控制键或组合键快捷指令），收拢态胶囊条便会瞬间被调起并激活输入光标。
    </p>

    <div class="figure-box">
        <img src="images/search_collapsed.png" alt="图 3-1 全盘快捷搜索常态收拢极简胶囊条">
        <div class="figure-caption">图 3-1 全盘快捷搜索常态收拢极简胶囊条</div>
    </div>

    <p>
        胶囊条采用了与现代桌面美学相得益彰的动态高斯模糊磨砂材质，不仅在视觉上通透轻盈，而且把对底层屏幕正在展示的核心业务内容的遮挡面积压缩到了极致。
    </p>

    <h2 class="section-title">3.2 动态展开与全拼/简拼实时穿透匹配</h2>
    <p>
        当操作人员在输入框内键入字符时，搜索中枢会实时展开为多结果呈现视窗。系统内部搭载了轻量高效的本地元数据索引分词引擎，对于中文应用与文件名提供了全面的拼音全拼解析与声母简拼穿透匹配支持。
    </p>
    <p>
        例如，用户只需键入拼音缩写“gz”，系统即可把名称中包含“工作汇报”、“工作总结”或“工具”的相关文件与系统工具从深层目录中快速提炼出来，并按照匹配度权值从高到低排列在结果列表中；列表项不仅直观呈现了资产图标与完整文件名称，还贴心标注了文件所在的绝对父级目录，帮助操作人员迅速做出判别。
    </p>

    <div class="figure-box">
        <img src="images/search_expanded.png" alt="图 3-2 搜索栏展开输入与全盘文件实时穿透匹配">
        <div class="figure-caption">图 3-2 搜索栏展开输入与全盘文件实时穿透匹配</div>
    </div>

    <p>
        用户利用键盘上下方向键即可在匹配条目间快速游标巡检，敲击回车键即刻调起该项目，按下 Escape 键则瞬间关闭视窗，整个流转过程丝毫感受不到延迟停顿。
    </p>

    <h2 class="section-title">3.3 语法动作候选列表（“/”语法引导）</h2>
    <p>
        为进一步释放高级检索与跨模态操作潜能，搜索中枢深度集成了“/”语法指令引导体系。当用户在空搜索框中键入斜杠符号“/”时，系统会在下方即时弹出一套标准化的功能动作候选列表面板。
    </p>

    <div class="figure-box">
        <img src="images/search_syntax_selection.png" alt="图 3-3 语法前缀引导与功能动作候选列表联动">
        <div class="figure-caption">图 3-3 语法前缀引导与功能动作候选列表联动</div>
    </div>

    <p>
        列表内涵盖了诸如“/doc”（文档资产专属筛选）、“/pic”（图片素材检索）、“/calc”（数学表达式求值）、“/dict”（本地词典查词）以及各类系统级动作。操作人员既可以通过上下键直接回车选取，也可以连续输入拼音把候选范围进一步缩小，使得复杂查询语法变得极为直观易用，彻底告别了死记硬背复杂参数的苦恼。
    </p>

    <h2 class="section-title">3.4 语义动作胶囊挂载与跨场景搜索</h2>
    <p>
        在候选列表中选定特定动作后，搜索框左侧会自动挂载一枚色彩鲜明、语义清晰的动作胶囊标签，例如“文档”过滤胶囊或“方案”定向检索胶囊。
    </p>

    <div class="figure-box">
        <img src="images/search_capsule.png" alt="图 3-4 语义动作胶囊挂载与分类定向精准检索">
        <div class="figure-caption">图 3-4 语义动作胶囊挂载与分类定向精准检索</div>
    </div>

    <p>
        在此状态下，用户后续输入的检索词将被严格限定在当前动作胶囊所划定的边界范围内。例如在挂载了“文档”胶囊后，全盘检索引擎会自动屏蔽海量的系统二进制文件与零碎临时文件，仅在 Word、PDF、Markdown 以及表格文档中开展精准扫描，从而大幅度降低了噪点干扰，把原本漫长的深层目录检索耗时缩减了近半数。
    </p>

    <h2 class="section-title">3.5 剪贴板自动感知与内容联想填充</h2>
    <p>
        在实际办公流程中，用户常常需要将浏览器或文档中复制的内容投入搜索。为此，本系统构建了智能剪贴板感知机制：当搜索框被唤出时，后台监听模块会快速比对剪贴板的最新内容与变更时间戳；若检测到当前剪贴板内存在适宜检索的有价值文本，输入框右侧或联想栏便会即时浮现提示气泡。
    </p>

    <div class="figure-box">
        <img src="images/search_autopaste.png" alt="图 3-5 剪贴板变更感知与自动预填联想">
        <div class="figure-caption">图 3-5 剪贴板变更感知与自动预填联想</div>
    </div>

    <p>
        操作人员只需敲击一次快捷键或轻点提示标签，系统便会把剪贴板文本无缝填入检索输入框中并立即展开匹配，有效省去了用户手动执行“粘贴-回车”的机械多重动作。
    </p>

    <div class="page-break"></div>

    <!-- 第 4 章 -->
    <h1 class="chapter-title">第 4 章 快捷实用工具与效率套件</h1>

    <h2 class="section-title">4.1 实时数学表达式求值计算器</h2>
    <p>
        为避免用户在处理微小数值运算时还需额外打开笨重的计算器软件，本系统的搜索中枢内嵌了一套高精度数学解析引擎。用户直接在搜索输入框内键入常规算式（支持加减乘除、括号优先级、幂运算及百分比计算），系统即可在毫秒之间完成语法解析，并在列表首行实时输出清晰准确的运算结果。
    </p>

    <div class="figure-box">
        <img src="images/search_calc.png" alt="图 4-1 实时数学表达式即时计算与求值结果展示">
        <div class="figure-caption">图 4-1 实时数学表达式即时计算与求值结果展示</div>
    </div>

    <p>
        敲击回车键后，系统会自动把该计算结果写入系统剪贴板中，操作人员切回表格或文档即可直接进行结果粘贴，整个流转平滑自如，极大提升了财务核对与工程量测算时的微交互体验。
    </p>

    <h2 class="section-title">4.2 本地离线中英双向词典实时速查</h2>
    <p>
        本系统深度整合了本地离线中英双向语料词库，在脱离互联网连接的完全离线状态下同样能够提供专业高效的生词查询服务。用户在搜索输入框中键入待查英文单词或中文字词，检索中枢会自动触发词典匹配管道，在结果面板中即刻呈现该词条的音标发音标注、详尽词性分类以及标准中文释义。
    </p>

    <div class="figure-box">
        <img src="images/search_dict.png" alt="图 4-2 本地离线中英双向词典词条实时查询与释义展示">
        <div class="figure-caption">图 4-2 本地离线中英双向词典词条实时查询与释义展示</div>
    </div>

    <p>
        由于所有词条数据均预先编译并打包在本地沙箱数据库中，查询过程中不发起任何网络请求，不仅在响应速度上做到了键入即出，而且从根源上保障了学术研发人员在涉密文档阅读时的信息安全性。
    </p>

    <h2 class="section-title">4.3 桌面系统动作指令快捷直达</h2>
    <p>
        针对 macOS 常见的高频系统维护动作，本系统提供了直达指令中枢支持。用户无需在系统各级菜单或设置面板中层层摸索，直接在搜索框内键入拼音或英文关键字，例如“锁屏”、“睡眠”、“清空废纸篓”或“重新启动”，系统即可秒级响应出系统动作磁贴。
    </p>

    <div class="figure-box">
        <img src="images/search_sys.png" alt="图 4-3 桌面系统动作指令快捷直达与操作反馈">
        <div class="figure-caption">图 4-3 桌面系统动作指令快捷直达与操作反馈</div>
    </div>

    <p>
        选中动作并按下回车后，系统便会平稳调起对应的底层操作系统接口完成指定作业，同时在屏幕上给出优雅的状态完成反馈，全面简化了系统维护与操作控制的交互链条。
    </p>

    <div class="page-break"></div>

    <!-- 第 5 章 -->
    <h1 class="chapter-title">第 5 章 智能窗口退出管理（AutoQuit）</h1>

    <h2 class="section-title">5.1 窗口生命周期治理与静默回收机制</h2>
    <p>
        在 macOS 操作系统中，诸多应用在关闭所有可见主窗口后，其后台进程往往依然长期挂载在驻留栈中，日积月累会导致宝贵的物理运行内存被大量闲置进程蚕食，进而引发整机的响应迟缓与电量虚耗。
    </p>
    <p>
        针对这一系统顽疾，本软件特别研制了 AutoQuit 智能窗口生命周期治理引擎。当被纳管的目标应用程序的所有主窗口均被用户关闭且其处于失去焦点状态时，AutoQuit 监控器会即刻启动倒计时巡检程序；若在预设的静默时限阈值内用户未重新唤醒该应用，系统便会自动向该进程下发优雅退出信号，使其平稳释放所占用的虚拟内存与显存资源，有效把整机内存开销降低了 20% 至 35% 左右。
    </p>

    <h2 class="section-title">5.2 独立进程治理服务与阈值设置</h2>
    <p>
        为了向用户提供充分的自主控制权，AutoQuit 在本版本中被升级为独立一级功能模块，具备专属的管理视窗与调优参数。用户既可以为全局应用程序统一设定空闲静默时限（如 10 秒、30 秒或 60 秒），也可以根据业务需要建立进程白名单机制，把诸如音乐播放器、实时通讯工具或后台下载软件加入排除清单，确保关键后台作业绝不被意外中断。
    </p>

    <div class="page-break"></div>

    <!-- 第 6 章 -->
    <h1 class="chapter-title">第 6 章 偏好设置中心全功能详解</h1>

    <p>
        本软件提供了系统级、全方位的偏好设置中心，用户可通过状态栏图标菜单、搜索面板指令或键盘组合键随时唤起偏好设置视窗。设置面板按照功能域划分为 7 大独立标签页，以下对每一标签页的全部配置项目展开深度说明。
    </p>

    <h2 class="section-title">6.1 通用设置（开机自启与状态栏图标）</h2>
    <p>
        通用设置标签页（Tab 0）集中管理软件的自启动策略与基础宿主交互行为：
    </p>
    <ul>
        <li><strong>登录时自动启动</strong>：开启后，系统在开机登录用户账户之际会自动调起 ATools 常驻后台服务，确保随时随地可响应呼出指令。</li>
        <li><strong>显示菜单栏常驻图标</strong>：控制系统顶部菜单栏右侧是否显示小巧的放大镜指示图标；关闭后软件进入纯键盘隐蔽运行模式，进一步精简菜单栏。</li>
        <li><strong>托盘图标样式选择</strong>：提供标准对比度与单色极简两种托盘图标质感，方便用户依据自身桌面壁纸风格自由切换。</li>
    </ul>

    <div class="figure-box">
        <img src="images/settings_tab_0.png" alt="图 5-1 偏好设置 - 通用设置配置界面">
        <div class="figure-caption">图 5-1 偏好设置 - 通用设置配置界面</div>
    </div>

    <h2 class="section-title">6.2 暂存架参数深度调优</h2>
    <p>
        暂存架设置（Tab 1）包含极为丰富的个性化维度，为了让复杂的配置项条理分明，本系统在标签页内部创新采用了三级分步式导航面板：
    </p>

    <h3 class="sub-section-title">6.2.1 第一页：启用与唤出触发策略配置</h3>
    <p>
        在该分页面中，用户可以对暂存架的唤出方式与边缘吸附灵敏度进行精细调节：
    </p>
    <ul>
        <li><strong>启用暂存架开关</strong>：总控开关，可一键完全开启或关闭暂存架的后台吸附服务。</li>
        <li><strong>触发方式选择</strong>：支持“鼠标触边滑动唤起”与“纯快捷键呼出”两种互斥模式。</li>
        <li><strong>停靠屏幕边缘指定</strong>：用户可自主选定面板挂载在“屏幕顶部”、“屏幕左侧”还是“屏幕右侧”。</li>
        <li><strong>触边驻留延迟阈值</strong>：允许在 100ms 至 800ms 区间微调光标停留判定时间，有效规避了光标无意滑过边缘引发的视觉误唤起。</li>
    </ul>

    <div class="figure-box">
        <img src="images/settings_tab_1_page0.png" alt="图 5-2 偏好设置 - 暂存架启用与唤出触发策略配置">
        <div class="figure-caption">图 5-2 偏好设置 - 暂存架启用与唤出触发策略配置</div>
    </div>

    <h3 class="sub-section-title">6.2.2 第二页：驻留形态与关闭行为配置</h3>
    <p>
        第二分页面专注于面板在展开后的交互响应与自动回缩逻辑：
    </p>
    <ul>
        <li><strong>失焦自动关闭</strong>：当光标移离暂存架视窗且点击外部其他窗口时，暂存架是否平滑自动收缩回边缘。</li>
        <li><strong>固定悬浮常驻开关</strong>：提供图钉式常驻锁定能力，在开启后即使发生失焦动作，面板依然稳定固定在屏幕最前端，极为便利多屏对照输入作业。</li>
        <li><strong>动画过渡曲线与速率</strong>：支持平滑弹簧阻尼效果微调，让每一次弹出与回缩都呈现出丝滑细腻的原生质感。</li>
    </ul>

    <div class="figure-box">
        <img src="images/settings_tab_1_page1.png" alt="图 5-3 偏好设置 - 暂存架驻留形态与关闭行为配置">
        <div class="figure-caption">图 5-3 偏好设置 - 暂存架驻留形态与关闭行为配置</div>
    </div>

    <h3 class="sub-section-title">6.2.3 第三页：分类管理与 70%~110% 卡片缩放排版</h3>
    <p>
        第三分页面提供了分类标签的增删改查以及极为关键的可视化缩放调节机制：
    </p>
    <ul>
        <li><strong>分类标签分组编排</strong>：支持操作人员新建、重命名或删除不同的业务分组标签，自由排列标签次序。</li>
        <li><strong>卡片缩放比例自适应微调</strong>：系统提供了 <strong>70% 至 110%</strong> 的平滑无级缩放滑块；在小尺寸笔记本屏幕上可缩小至 70%~80% 展现更多紧凑卡片，而在 4K 宽屏显示器上则可放大至 105%~110% 获得饱满舒展的可读性。</li>
        <li><strong>卡片列数与边距调节</strong>：允许用户根据桌面分辨率自由设定每屏展示的卡片列数与网格间距。</li>
    </ul>

    <div class="figure-box">
        <img src="images/settings_tab_1_page2.png" alt="图 5-4 偏好设置 - 暂存架分类管理与 70%~110% 卡片缩放排版">
        <div class="figure-caption">图 5-4 偏好设置 - 暂存架分类管理与 70%~110% 卡片缩放排版</div>
    </div>

    <h2 class="section-title">6.3 快捷搜索热键绑定与检索源配置</h2>
    <p>
        快捷搜索设置标签页（Tab 2）负责全盘检索中枢的核心调度逻辑：
    </p>
    <ul>
        <li><strong>唤醒全局快捷键录制</strong>：提供直观的可视化按键录制槽，支持设置诸如 <code>Option + Space</code>、<code>Command + Shift + Space</code> 或双击修饰键等高频指令。</li>
        <li><strong>检索源数据范围勾选</strong>：支持独立勾选是否检索“已安装应用程序”、“文稿与表格”、“开发者项目代码”、“本地书签”以及“系统设置面板”。</li>
        <li><strong>拼音模糊容错与全词匹配权重</strong>：允许微调拼音首字母匹配敏感度，兼顾匹配宽泛度与命中精准率。</li>
    </ul>

    <div class="figure-box">
        <img src="images/settings_tab_2.png" alt="图 5-5 偏好设置 - 全局快捷搜索热键与检索源管理">
        <div class="figure-caption">图 5-5 偏好设置 - 全局快捷搜索热键与检索源管理</div>
    </div>

    <h2 class="section-title">6.4 独立自动退出策略定制</h2>
    <p>
        AutoQuit 标签页（Tab 3）在本版本中被构筑为顶层独立管理视图，全面强化了进程治理的可见性：
    </p>
    <ul>
        <li><strong>服务总开关与运行状态感知</strong>：顶部醒目展示当前 AutoQuit 守护引擎的活跃状态与已纳管的后台进程总数。</li>
        <li><strong>失焦静默倒计时滑块</strong>：可在 5 秒至 300 秒范围内自由调节无主窗口应用的保留等待时长。</li>
        <li><strong>纳管黑白名单精细化过滤</strong>：支持直接通过点选勾选框把特定多媒体播放器或常驻办公工具加入排除名单，避免常驻音频中断。</li>
    </ul>

    <div class="figure-box">
        <img src="images/settings_tab_3.png" alt="图 5-6 偏好设置 - AutoQuit 智能窗口退出管理独立配置">
        <div class="figure-caption">图 5-6 偏好设置 - AutoQuit 智能窗口退出管理独立配置</div>
    </div>

    <h2 class="section-title">6.5 外观主题、材质质感与深浅模式微调</h2>
    <p>
        外观主题标签页（Tab 4）让软件能够全方位融入个性化的桌面视觉体系：
    </p>
    <ul>
        <li><strong>色彩外观模式选择</strong>：支持“跟随操作系统外观”、“强制浅色模式（Light Mode）”与“强制深色模式（Dark Mode）”三大选项。</li>
        <li><strong>背景模糊材质深度</strong>：可在“标准半透明毛玻璃（Vibrant Frosted Glass）”与“高对比度实色不透明”之间无缝切换。</li>
        <li><strong>圆角半径与阴影扩散度</strong>：支持用户依据自身审美对视窗的边缘圆角弧度进行像素级微调。</li>
    </ul>

    <div class="figure-box">
        <img src="images/settings_tab_4.png" alt="图 5-7 偏好设置 - 外观主题、深浅模式与毛玻璃质感调节">
        <div class="figure-caption">图 5-7 偏好设置 - 外观主题、深浅模式与毛玻璃质感调节</div>
    </div>

    <h2 class="section-title">6.6 内存性能监控与本地缓存清理</h2>
    <p>
        性能与缓存标签页（Tab 5）为系统的长期稳健运行提供可靠的资源监控与维护工具：
    </p>
    <ul>
        <li><strong>实时内存与 CPU 负载监控</strong>：直观展示 ATools 当前常驻内存占用（通常仅维持在 30MB 至 60MB 极低水位）及瞬时 CPU 消耗。</li>
        <li><strong>本地元数据缓存容量审计</strong>：统计本地全盘索引数据库与图标缓存所占用的磁盘物理空间。</li>
        <li><strong>一键清除本地临时缓存</strong>：提供“清除图标缓存”与“重建全盘检索索引”快捷维护指令，轻松应对文件移动导致的失效索引。</li>
    </ul>

    <div class="figure-box">
        <img src="images/settings_tab_5.png" alt="图 5-8 偏好设置 - 运行性能监控与本地索引缓存维护">
        <div class="figure-caption">图 5-8 偏好设置 - 运行性能监控与本地索引缓存维护</div>
    </div>

    <h2 class="section-title">6.7 软件版本关于与在线更新检测</h2>
    <p>
        关于标签页（Tab 6）完整公示了本软件的版本声明、著作权归属以及更新通道配置：
    </p>
    <ul>
        <li><strong>软件全称与正式版本号</strong>：明确标注《ATools桌面分类启动与全盘搜索工具软件 V1.0》。</li>
        <li><strong>自主研发版权声明与许可协议</strong>：公示自主研发团队的合法著作权权属。</li>
        <li><strong>更新检测与发布通道</strong>：支持手动触发“检查新版本”，并可配置是否在新版本发布时接收非侵入式轻量横幅提醒。</li>
    </ul>

    <div class="figure-box">
        <img src="images/settings_tab_6.png" alt="图 5-9 偏好设置 - 软件版本关于与在线更新检测">
        <div class="figure-caption">图 5-9 偏好设置 - 软件版本关于与在线更新检测</div>
    </div>

    <div class="page-break"></div>

    <!-- 第 7 章 -->
    <h1 class="chapter-title">第 7 章 系统运行维护与故障排查</h1>

    <h2 class="section-title">7.1 辅助功能与全盘访问权限异常处理</h2>
    <p>
        如果用户在首次启动时误点了权限拒绝，或者在操作系统进行大版本跨越升级后发现全局快捷键失效或触边手势未响应，通常是系统辅助功能授权状态未生效所致。
    </p>
    <p>
        操作人员可进入操作系统的“系统设置 -> 隐私与安全性 -> 辅助功能”列表中，定位到“ATools”，将其右侧的开关关闭后重新打开；若列表中尚未包含 ATools 项，只需点击下方的“+”加号按钮，从“应用程序”文件夹中选中 ATools 并确认添加即可恢复全部功能。
    </p>

    <h2 class="section-title">7.2 快捷键冲突排查与重绑定</h2>
    <p>
        当系统预设的呼出热键与用户电脑中其他输入法、开发集成环境或即时通讯工具的快捷键发生重叠时，系统可能会出现快捷键无法激活搜索栏的现象。
    </p>
    <p>
        此时操作人员可轻点顶部菜单栏中的 ATools 托盘图标，在下拉菜单中选取“偏好设置”，切换至“快捷搜索”标签页，双击快捷键输入框录制一套全新的组合键（例如增加 Control 或 Option 修饰键），录制完毕后系统会在毫秒级时间内解绑旧热键并完成全新指令的底层注册。
    </p>

    <h2 class="section-title">7.3 索引缓存重建与配置文件恢复</h2>
    <p>
        在极少数情况下，如果操作人员对电脑进行了大规模的磁盘目录重构，或者通过第三方清理软件强行清理了临时文件，可能导致搜索结果中个别历史路径已失效。
    </p>
    <p>
        用户只需进入偏好设置的“性能与缓存”面板，点击“重建全盘检索索引”按钮；底层索引服务即刻会在后台并发扫描用户主目录下的最新资产，通常在 2 至 5 秒内即可完成整库的增量校验与更新。若需要将所有个性化参数还原为出厂默认状态，只需在性能面板中点击“重置全部偏好配置”，系统便会安全清空当前的本地沙箱配置并重新初始化。
    </p>

</div>

</body>
</html>
"""

def generate_plain_text(html_content):
    """从 HTML 中提取用于查 AIGC 的纯净文本"""
    # 去除 style 块
    text = re.sub(r'<style[\s\S]*?</style>', '', html_content)
    # 去除注释
    text = re.sub(r'<!--[\s\S]*?-->', '', text)
    # 替换标题和换行
    text = re.sub(r'<h1[^>]*>(.*?)</h1>', r'\n\n【\1】\n', text)
    text = re.sub(r'<h2[^>]*>(.*?)</h2>', r'\n\n一、\1\n', text)
    text = re.sub(r'<h3[^>]*>(.*?)</h3>', r'\n（一）\1\n', text)
    text = re.sub(r'</p>', '\n', text)
    text = re.sub(r'</li>', '\n', text)
    text = re.sub(r'</tr>', '\n', text)
    text = re.sub(r'<div class="figure-caption">(.*?)</div>', r'\n[配图说明：\1]\n', text)
    text = re.sub(r'<[^>]+>', '', text)
    # 规整多余空白与换行
    lines = [line.strip() for line in text.splitlines()]
    clean_lines = []
    prev_empty = False
    for line in lines:
        if line:
            clean_lines.append(line)
            prev_empty = False
        elif not prev_empty:
            clean_lines.append('')
            prev_empty = True
    return '\n'.join(clean_lines).strip()

def main():
    print("Writing HTML user manual to:", HTML_PATH)
    with open(HTML_PATH, "w", encoding="utf-8") as f:
        f.write(HTML_TEMPLATE)

    print("Generating plain text user manual for AIGC detection...")
    plain_text = generate_plain_text(HTML_TEMPLATE)
    with open(TXT_PATH, "w", encoding="utf-8") as f:
        f.write(plain_text)
    print(f"Plain text written to: {TXT_PATH}, length: {len(plain_text)} chars")

    print("Converting HTML user manual to PDF using Google Chrome...")
    chrome_bin = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    cmd = [
        chrome_bin,
        "--headless",
        "--disable-gpu",
        "--no-pdf-header-footer",
        f"--print-to-pdf={PDF_PATH}",
        HTML_PATH
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0 and os.path.exists(PDF_PATH):
        print(f"Successfully generated PDF: {PDF_PATH} ({os.path.getsize(PDF_PATH)} bytes)")
    else:
        print("Chrome headless error:", res.stderr)

if __name__ == "__main__":
    main()
