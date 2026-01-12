#include "ui/MarkdownBlocks.hpp"

#include <QRegularExpression>
#include <QStringList>
#include <algorithm>
#include <optional>

namespace zinc::ui {

namespace {

QString trim_right_newlines(QString s) {
    while (s.endsWith('\n')) {
        s.chop(1);
    }
    return s;
}

QVariantMap make_block(const QString& type,
                       const QString& content,
                       int depth = 0,
                       bool checked = false,
                       bool collapsed = false,
                       const QString& language = {},
                       int headingLevel = 0) {
    QVariantMap block;
    block["blockType"] = type;
    block["content"] = content;
    block["depth"] = depth;
    block["checked"] = checked;
    block["collapsed"] = collapsed;
    block["language"] = language;
    block["headingLevel"] = headingLevel;
    return block;
}

QString link_to_markdown(const QString& content) {
    const auto parts = content.split('|');
    const auto pageId = parts.value(0);
    const auto title = parts.value(1, QStringLiteral("Untitled"));
    return QStringLiteral("[%1](zinc://page/%2)").arg(title, pageId);
}

std::optional<QString> parse_link(const QString& line) {
    static const QRegularExpression re(
        R"(^\[(.*)\]\(zinc://page/([^)]+)\)\s*$)");
    const auto m = re.match(line);
    if (!m.hasMatch()) return std::nullopt;
    const auto title = m.captured(1);
    const auto pageId = m.captured(2);
    return pageId + "|" + title;
}

bool is_bulleted_list_item(const QString& line) {
    static const QRegularExpression bulletRe(R"(^\s*-\s+(?!\[).+$)");
    return bulletRe.match(line).hasMatch();
}

} // namespace

MarkdownBlocks::MarkdownBlocks(QObject* parent)
    : QObject(parent) {
}

QString MarkdownBlocks::headerLine() {
    return QStringLiteral("<!-- zinc-blocks v1 -->");
}

bool MarkdownBlocks::isZincBlocksPayload(const QString& markdown) const {
    const auto lines = markdown.split('\n');
    for (const auto& line : lines) {
        const auto trimmed = line.trimmed();
        if (trimmed.isEmpty()) continue;
        return trimmed == headerLine();
    }
    return false;
}

QString MarkdownBlocks::serialize(const QVariantList& blocks) const {
    QStringList out;
    out << headerLine();

    auto emit_block = [&](const QString& s) {
        out << s;
        out << QString();
    };

    for (const auto& entry : blocks) {
        const auto block = entry.toMap();
        const auto type = block.value("blockType").toString();
        const auto content = block.value("content").toString();
        const auto depth = block.value("depth").toInt();
        const auto checked = block.value("checked").toBool();
        const auto collapsed = block.value("collapsed").toBool();
        const auto language = block.value("language").toString();
        const auto headingLevel = block.value("headingLevel").toInt();

        if (type == "heading") {
            const int level = std::clamp(headingLevel == 0 ? 1 : headingLevel, 1, 3);
            emit_block(QString(level, QChar('#')) + " " + content);
        } else if (type == "todo") {
            const auto indent = QString(depth * 2, QChar(' '));
            emit_block(indent + "- [" + (checked ? "x" : " ") + "] " + content);
        } else if (type == "quote") {
            const auto lines = content.split('\n');
            QStringList quoted;
            quoted.reserve(lines.size());
            for (const auto& line : lines) {
                quoted << (QStringLiteral("> ") + line);
            }
            emit_block(quoted.join('\n'));
        } else if (type == "code") {
            QString fence = QStringLiteral("```");
            if (!language.isEmpty()) {
                fence += language;
            }
            const auto body = trim_right_newlines(content);
            emit_block(fence + "\n" + body + "\n```");
        } else if (type == "divider") {
            emit_block(QStringLiteral("---"));
        } else if (type == "bulleted") {
            emit_block(trim_right_newlines(content));
        } else if (type == "toggle") {
            const auto openAttr = collapsed ? QString() : QStringLiteral(" open");
            emit_block(QStringLiteral("<details%1><summary>%2</summary></details>")
                           .arg(openAttr, content));
        } else if (type == "link") {
            emit_block(link_to_markdown(content));
        } else {
            emit_block(content);
        }
    }

    while (!out.isEmpty() && out.last().isEmpty()) {
        out.removeLast();
    }
    return out.join('\n') + "\n";
}

QString MarkdownBlocks::serializeContent(const QVariantList& blocks) const {
    QStringList out;

    auto emit_block = [&](const QString& s) {
        out << s;
        out << QString();
    };

    for (const auto& entry : blocks) {
        const auto block = entry.toMap();
        const auto type = block.value("blockType").toString();
        const auto content = block.value("content").toString();
        const auto depth = block.value("depth").toInt();
        const auto checked = block.value("checked").toBool();
        const auto collapsed = block.value("collapsed").toBool();
        const auto language = block.value("language").toString();
        const auto headingLevel = block.value("headingLevel").toInt();

        if (type == "heading") {
            const int level = std::clamp(headingLevel == 0 ? 1 : headingLevel, 1, 3);
            emit_block(QString(level, QChar('#')) + " " + content);
        } else if (type == "todo") {
            const auto indent = QString(depth * 2, QChar(' '));
            emit_block(indent + "- [" + (checked ? "x" : " ") + "] " + content);
        } else if (type == "quote") {
            const auto lines = content.split('\n');
            QStringList quoted;
            quoted.reserve(lines.size());
            for (const auto& line : lines) {
                quoted << (QStringLiteral("> ") + line);
            }
            emit_block(quoted.join('\n'));
        } else if (type == "code") {
            QString fence = QStringLiteral("```");
            if (!language.isEmpty()) {
                fence += language;
            }
            const auto body = trim_right_newlines(content);
            emit_block(fence + "\n" + body + "\n```");
        } else if (type == "divider") {
            emit_block(QStringLiteral("---"));
        } else if (type == "bulleted") {
            emit_block(trim_right_newlines(content));
        } else if (type == "toggle") {
            const auto openAttr = collapsed ? QString() : QStringLiteral(" open");
            emit_block(QStringLiteral("<details%1><summary>%2</summary></details>")
                           .arg(openAttr, content));
        } else if (type == "link") {
            emit_block(link_to_markdown(content));
        } else {
            emit_block(content);
        }
    }

    while (!out.isEmpty() && out.last().isEmpty()) {
        out.removeLast();
    }
    return out.join('\n') + "\n";
}

QVariantList MarkdownBlocks::parse(const QString& markdown) const {
    QStringList lines = markdown.split('\n');
    while (!lines.isEmpty() && lines.last().isEmpty()) {
        lines.removeLast();
    }

    int start = 0;
    for (; start < lines.size(); ++start) {
        if (!lines[start].trimmed().isEmpty()) break;
    }
    if (start < lines.size() && lines[start].trimmed() == headerLine()) {
        ++start;
    }

    QVariantList blocks;

    auto emit_paragraph = [&](QStringList& buffer) {
        if (buffer.isEmpty()) return;
        blocks.append(make_block("paragraph", buffer.join('\n')));
        buffer.clear();
    };

    QStringList paragraph;
    for (int i = start; i < lines.size(); ++i) {
        const auto line = lines[i];
        const auto trimmed = line.trimmed();

        if (is_bulleted_list_item(line)) {
            emit_paragraph(paragraph);

            QStringList listLines;
            listLines << line;
            const int baseIndent = line.indexOf('-');
            for (++i; i < lines.size(); ++i) {
                const auto next = lines[i];
                if (next.trimmed().isEmpty()) {
                    --i;
                    break;
                }
                if (is_bulleted_list_item(next)) {
                    listLines << next;
                    continue;
                }
                // Continuation line: indented beyond the bullet level.
                const int nonSpace = next.indexOf(QRegularExpression("\\S"));
                if (nonSpace >= 0 && nonSpace > baseIndent) {
                    listLines << next;
                    continue;
                }
                --i;
                break;
            }
            blocks.append(make_block("bulleted", listLines.join('\n')));
            continue;
        }

        if (trimmed.startsWith("```")) {
            emit_paragraph(paragraph);

            const auto language = trimmed.mid(3).trimmed();
            QStringList code;
            for (++i; i < lines.size(); ++i) {
                if (lines[i].trimmed() == "```") {
                    break;
                }
                code << lines[i];
            }
            blocks.append(make_block("code", code.join('\n'), 0, false, false, language));
            continue;
        }

        if (trimmed.startsWith("<details")) {
            emit_paragraph(paragraph);

            static const QRegularExpression detailsRe(
                R"(^<details(\s+open)?>\s*<summary>(.*)</summary>\s*</details>\s*$)");
            const auto m = detailsRe.match(trimmed);
            if (m.hasMatch()) {
                const bool open = !m.captured(1).isEmpty();
                const auto summary = m.captured(2);
                blocks.append(make_block("toggle", summary, 0, false, !open));
                continue;
            }
        }

        if (trimmed == "---") {
            emit_paragraph(paragraph);
            blocks.append(make_block("divider", QString()));
            continue;
        }

        static const QRegularExpression headingRe(R"(^(#{1,3})\s+(.*)$)");
        if (auto m = headingRe.match(trimmed); m.hasMatch()) {
            emit_paragraph(paragraph);
            const int level = m.captured(1).size();
            blocks.append(make_block("heading", m.captured(2), 0, false, false, {}, level));
            continue;
        }

        static const QRegularExpression todoRe(R"(^(\s*)-\s+\[([ xX])\]\s+(.*)$)");
        if (auto m = todoRe.match(line); m.hasMatch()) {
            emit_paragraph(paragraph);
            const auto spaces = m.captured(1).size();
            const int depth = spaces / 2;
            const bool checked = m.captured(2).trimmed().toLower() == "x";
            blocks.append(make_block("todo", m.captured(3), depth, checked));
            continue;
        }

        if (trimmed.startsWith(">")) {
            emit_paragraph(paragraph);
            QStringList quoted;
            for (; i < lines.size(); ++i) {
                const auto t = lines[i].trimmed();
                if (!t.startsWith(">")) {
                    --i;
                    break;
                }
                auto q = t.mid(1);
                if (q.startsWith(' ')) q = q.mid(1);
                quoted << q;
            }
            blocks.append(make_block("quote", quoted.join('\n')));
            continue;
        }

        if (auto link = parse_link(line)) {
            emit_paragraph(paragraph);
            blocks.append(make_block("link", *link));
            continue;
        }

        if (trimmed.isEmpty()) {
            emit_paragraph(paragraph);
            continue;
        }

        paragraph << line;
    }

    emit_paragraph(paragraph);
    return blocks;
}

QVariantList MarkdownBlocks::parseWithSpans(const QString& markdown) const {
    struct Line {
        int start = 0;
        int end = 0; // exclusive, includes newline if present
        QString view;
        QString trimmed;
    };

    QVector<Line> lines;
    lines.reserve(markdown.size() / 20);

    int pos = 0;
    while (pos <= markdown.size()) {
        const int lineStart = pos;
        int lineEnd = markdown.indexOf('\n', pos);
        bool hasNewline = true;
        if (lineEnd < 0) {
            lineEnd = markdown.size();
            hasNewline = false;
        }
        const int lineEndWithNewline = hasNewline ? (lineEnd + 1) : lineEnd;
        const QString lineText = markdown.mid(lineStart, lineEnd - lineStart);
        lines.push_back(Line{
            .start = lineStart,
            .end = lineEndWithNewline,
            .view = lineText,
            .trimmed = lineText.trimmed(),
        });
        if (!hasNewline) break;
        pos = lineEndWithNewline;
    }

    int i = 0;
    while (i < lines.size() && lines[i].trimmed.isEmpty()) ++i;
    if (i < lines.size() && lines[i].trimmed == headerLine()) {
        ++i;
        while (i < lines.size() && lines[i].trimmed.isEmpty()) ++i;
    }

    QVariantList out;
    auto addBlock = [&](const QVariantMap& block, int startOffset, int endOffset) {
        QVariantMap entry = block;
        entry["start"] = startOffset;
        entry["end"] = endOffset;
        entry["raw"] = markdown.mid(startOffset, endOffset - startOffset);
        out.append(entry);
    };

    auto makeParagraph = [&](int startLine, int endLineInclusive) {
        QStringList parts;
        parts.reserve(endLineInclusive - startLine + 1);
        for (int k = startLine; k <= endLineInclusive; ++k) {
            parts << lines[k].view;
        }
        return parts.join('\n');
    };

    while (i < lines.size()) {
        while (i < lines.size() && lines[i].trimmed.isEmpty()) ++i;
        if (i >= lines.size()) break;

        const int blockStartLine = i;
        const int blockStartOffset = lines[i].start;
        const auto trimmed = lines[i].trimmed;

        if (trimmed.startsWith("```")) {
            const auto language = trimmed.mid(3).trimmed();
            QStringList code;
            int j = i + 1;
            for (; j < lines.size(); ++j) {
                if (lines[j].trimmed == "```") {
                    break;
                }
                code << lines[j].view;
            }
            const int endLine = (j < lines.size()) ? j : (lines.size() - 1);
            const int blockEndOffset = lines[endLine].end;
            addBlock(make_block("code", code.join('\n'), 0, false, false, language),
                     blockStartOffset, blockEndOffset);
            i = endLine + 1;
            continue;
        }

        static const QRegularExpression detailsRe(
            R"(^<details(\s+open)?>\s*<summary>(.*)</summary>\s*</details>\s*$)");
        if (auto m = detailsRe.match(trimmed); m.hasMatch()) {
            const bool open = !m.captured(1).isEmpty();
            addBlock(make_block("toggle", m.captured(2), 0, false, !open),
                     blockStartOffset, lines[i].end);
            i = i + 1;
            continue;
        }

        if (trimmed == "---") {
            addBlock(make_block("divider", QString()), blockStartOffset, lines[i].end);
            i = i + 1;
            continue;
        }

        static const QRegularExpression headingRe(R"(^(#{1,3})\s+(.*)$)");
        if (auto m = headingRe.match(trimmed); m.hasMatch()) {
            const int level = m.captured(1).size();
            addBlock(make_block("heading", m.captured(2), 0, false, false, {}, level),
                     blockStartOffset, lines[i].end);
            i = i + 1;
            continue;
        }

        static const QRegularExpression todoRe(R"(^(\s*)-\s+\[([ xX])\]\s+(.*)$)");
        if (auto m = todoRe.match(lines[i].view); m.hasMatch()) {
            const int spaces = m.captured(1).size();
            const int depth = spaces / 2;
            const bool checked = m.captured(2).trimmed().toLower() == "x";
            addBlock(make_block("todo", m.captured(3), depth, checked),
                     blockStartOffset, lines[i].end);
            i = i + 1;
            continue;
        }

        if (is_bulleted_list_item(lines[i].view)) {
            QStringList listLines;
            listLines << lines[i].view;
            const int baseIndent = lines[i].view.indexOf('-');
            int j = i + 1;
            for (; j < lines.size(); ++j) {
                if (lines[j].trimmed.isEmpty()) break;
                if (is_bulleted_list_item(lines[j].view)) {
                    listLines << lines[j].view;
                    continue;
                }
                const int nonSpace = lines[j].view.indexOf(QRegularExpression("\\S"));
                if (nonSpace >= 0 && nonSpace > baseIndent) {
                    listLines << lines[j].view;
                    continue;
                }
                break;
            }
            const int endLine = j - 1;
            addBlock(make_block("bulleted", listLines.join('\n')),
                     blockStartOffset, lines[endLine].end);
            i = j;
            continue;
        }

        if (trimmed.startsWith(">")) {
            QStringList quoted;
            int j = i;
            for (; j < lines.size(); ++j) {
                const auto t = lines[j].trimmed;
                if (!t.startsWith(">")) break;
                auto q = t.mid(1);
                if (q.startsWith(' ')) q = q.mid(1);
                quoted << q;
            }
            const int endLine = j - 1;
            addBlock(make_block("quote", quoted.join('\n')),
                     blockStartOffset, lines[endLine].end);
            i = j;
            continue;
        }

        if (auto link = parse_link(lines[i].view)) {
            addBlock(make_block("link", *link), blockStartOffset, lines[i].end);
            i = i + 1;
            continue;
        }

        int j = i;
        for (; j < lines.size(); ++j) {
            if (lines[j].trimmed.isEmpty()) break;
        }
        const int endLine = j - 1;
        addBlock(make_block("paragraph", makeParagraph(blockStartLine, endLine)),
                 blockStartOffset, lines[endLine].end);
        i = j + 1;
    }

    return out;
}

} // namespace zinc::ui
