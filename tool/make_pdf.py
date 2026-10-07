"""Builds dist/BCR-LeadBook-Install-and-User-Guide.pdf from docs/screens/*.png."""
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import cm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Image, Table,
                                TableStyle, PageBreak, KeepTogether)

F = r'C:\Bibin\_tools\flutter\bin\cache\artifacts\material_fonts'
pdfmetrics.registerFont(TTFont('R', F + r'\roboto-regular.ttf'))
pdfmetrics.registerFont(TTFont('RB', F + r'\roboto-bold.ttf'))
pdfmetrics.registerFont(TTFont('RM', F + r'\roboto-medium.ttf'))

pdfmetrics.registerFontFamily('R', normal='R', bold='RB', italic='R', boldItalic='RB')

BLUE = colors.HexColor('#1565C0')
INK = colors.HexColor('#14202E')
MUTED = colors.HexColor('#4A5A6B')

h1 = ParagraphStyle('h1', fontName='RB', fontSize=24, leading=28, textColor=BLUE, spaceAfter=4)
sub = ParagraphStyle('sub', fontName='R', fontSize=11.5, leading=15, textColor=MUTED, spaceAfter=10)
h2 = ParagraphStyle('h2', fontName='RB', fontSize=15, leading=19, textColor=BLUE, spaceBefore=10, spaceAfter=5)
body = ParagraphStyle('body', fontName='R', fontSize=10, leading=13.5, textColor=INK, spaceAfter=4)
step = ParagraphStyle('step', parent=body, leftIndent=16, firstLineIndent=-16, spaceAfter=3)
cap = ParagraphStyle('cap', fontName='RM', fontSize=9.5, leading=12, textColor=MUTED, alignment=1, spaceBefore=3)
note = ParagraphStyle('note', parent=body, backColor=colors.HexColor('#FFF6E0'), borderPadding=6,
                      borderColor=colors.HexColor('#E9C46A'), borderWidth=0.6, spaceBefore=6, spaceAfter=8)
sig = ParagraphStyle('sig', fontName='R', fontSize=9, textColor=MUTED, alignment=1)


def P(t, s=body):
    return Paragraph(t, s)


def steps(items):
    return [P(f'<b>{i}.</b>&nbsp;&nbsp;{t}', step) for i, t in enumerate(items, 1)]


def shot(name, text, w=5.5 * cm):
    path = f'docs/screens/{name}.png'
    from PIL import Image as PI
    iw, ih = PI.open(path).size
    img = Image(path, width=w, height=w * ih / iw)
    img.hAlign = 'CENTER'
    t = Table([[img], [P(text, cap)]], colWidths=[w + 0.4 * cm])
    t.setStyle(TableStyle([('BOX', (0, 0), (0, 0), 0.8, colors.HexColor('#C5D3E3')),
                           ('LEFTPADDING', (0, 0), (-1, -1), 2), ('RIGHTPADDING', (0, 0), (-1, -1), 2),
                           ('TOPPADDING', (0, 0), (-1, -1), 2), ('BOTTOMPADDING', (0, 0), (-1, -1), 2)]))
    return t


def pair(a, b):
    t = Table([[a, b]], colWidths=[8.6 * cm, 8.6 * cm])
    t.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'TOP'), ('ALIGN', (0, 0), (-1, -1), 'CENTER')]))
    return t


def footer(c, d):
    c.saveState()
    c.setFont('R', 8.5)
    c.setFillColor(MUTED)
    c.drawCentredString(A4[0] / 2, 1.0 * cm, f'BCR LeadBook 1.0.0  \u00b7  BCR (BibinCutRiver)  \u00b7  page {d.page}')
    c.restoreState()


doc = SimpleDocTemplate('dist/BCR-LeadBook-Install-and-User-Guide.pdf', pagesize=A4,
                        leftMargin=1.8 * cm, rightMargin=1.8 * cm, topMargin=1.6 * cm, bottomMargin=1.7 * cm,
                        title='BCR LeadBook: Install and User Guide', author='BCR (BibinCutRiver)')
s = []

# ---- page 1: install
s += [P('BCR LeadBook', h1),
      P('Install on Android and quick user guide. Record a client meeting in under five minutes, then remember '
        'every detail before the next call. Works offline: no account, no internet, no subscription.', sub),
      P('Part 1: Install the app (about 2 minutes)', h2)]
s += steps([
    '<b>Get the file</b> <i>BCR-LeadBook-1.0.0.apk</i> (about 59 MB) onto your phone: send it to yourself by WhatsApp, '
    'email or Google Drive, or connect the phone by USB and copy it to <i>Downloads</i>. Needs Android 7.0 or newer.',
    '<b>Open the file</b> on the phone (Files / Downloads app, or tap it inside WhatsApp / Gmail).',
    'If Android says <i>your phone isn\u2019t allowed to install unknown apps from this source</i>, tap <b>Settings</b>, switch on '
    '<b>Allow from this source</b>, press Back, then tap <b>Install</b>.',
    'If <i>Google Play Protect</i> shows \u201cApp not scanned\u201d or \u201cunknown developer\u201d, tap <b>More details &gt; Install anyway</b>. '
    'This only appears because the app is installed from a file instead of the Play Store.',
    'Tap <b>Open</b>, then <b>Get started</b> on the Welcome screen.',
    'The first time you save a follow-up with a reminder, tap <b>Allow</b> when the phone asks about notifications.'])
s += [P('<b>Good to know.</b> To update, install the newer APK over the old one; your data stays. '
        '<b>Do not uninstall</b> the app without making a backup first: uninstalling deletes all records. '
        'On Xiaomi, Oppo, Vivo, Huawei or Samsung phones with aggressive battery saving, set '
        '<i>Settings &gt; Apps &gt; BCR LeadBook &gt; Battery &gt; Unrestricted</i> so reminders arrive on time.', note),
      P('Part 2: Using the app', h2),
      P('The app has four tabs along the bottom: <b>Home</b> (what needs attention today), <b>Leads</b> (all your companies, '
        'searchable), <b>Follow-ups</b> (your to-do list) and <b>Settings</b> (backup, export, reminders).'),
      P('Screenshots in this guide are rendered from the real app screens with sample data (companies marked \u201cdemo\u201d and '
        '\u201cSample Person\u201d are fictional).', sub),
      PageBreak()]

# ---- page 2: welcome + home
s += [pair(shot('01_welcome', 'Welcome screen: tap Get started'),
           shot('02_home', 'Home: today\u2019s follow-ups, hot leads, renewals')),
      Spacer(1, 8), P('Home screen', h2)]
s += steps([
    '<b>Add Lead / Meeting</b> is the big blue button. Use it after every meeting.',
    'The three boxes show how many follow-ups are <b>overdue</b>, <b>due today</b>, and how many <b>hot leads</b> you have. Tap one to see them.',
    'Scroll down for <b>Upcoming renewals</b> (policies expiring in the next 90 days) and <b>Recently updated</b> companies.',
    'The yellow card reminds you to <b>back up</b> your data. A second yellow card appears if you left a form unfinished: tap it to resume.',
    'On any follow-up, tap the <b>phone</b> or <b>chat</b> icon to call or WhatsApp the contact. The app only opens the phone or WhatsApp; it never sends anything by itself.'])
s += [PageBreak()]

# ---- page 3: form
s += [pair(shot('03_form_top', 'Add Lead / Meeting: company, quality, people, products'),
           shot('04_form_notes', 'The three note boxes and next action')),
      Spacer(1, 8), P('Recording a meeting (under 5 minutes)', h2)]
s += steps([
    'Type the <b>Company name</b>. This is the only required field; everything else can be added later. '
    'If a similar company is already saved, the app offers <b>Open it</b>; tap <i>This is a different company</i> if it is not the same business.',
    'Pick a <b>Lead quality</b> (Hot, Warm, Cold, Future Follow-Up). Tap it again to un-choose. Optionally set the <b>target follow-up month</b>.',
    '<b>Add the person you met</b> (name is enough; add phone with country code, e.g. +971 50 123 4567). '
    'Next time just pick them from the list. For the next call with someone else (e.g. the decision-maker), switch off \u201cNext call is with the same person\u201d.',
    '<b>Add Product</b> for each policy (Medical, Motor, Property, Marine, Liability, Other). Set the expiry date, or leave it unknown. '
    'Use <b>Add Another Product</b> for more.',
    'Write your notes: <b>Meeting Summary &amp; Minor Details</b> (discussion, requirements, objections, promises, next steps), '
    '<b>Personal &amp; Rapport Notes</b> (hobbies, family, coffee order, favourite team; kept with the person for every future meeting) and '
    '<b>Company Trivia &amp; Context</b> (expansion plans, news).',
    '<b>Next action</b>: type it, tap a day (Mon\u2013Fri, Tomorrow, Next week\u2026) and keep <b>Remind me</b> on (9:00 AM by default).',
    'Tap <b>Save</b>. A green \u201cSaved\u201d message confirms it. If you are interrupted, your work is kept as a draft.'])
s += [PageBreak()]

# ---- page 4: leads + precall
s += [pair(shot('05_leads', 'Leads: search, filter, sort'),
           shot('06_precall', 'Company page, Pre-call tab')),
      Spacer(1, 8), P('Finding clients and preparing for a call', h2)]
s += steps([
    '<b>Leads</b> tab: type in the search box to find a company, contact name, phone number (with or without +971 or a leading 0) '
    'or any word from your notes. <b>Filters</b> narrow by quality, target month, insurance line and follow-up status; <b>Sort</b> by next follow-up, '
    'latest update, name or nearest policy expiry. Colours always come with a text label.',
    'Tap a company to open it. The <b>Pre-call</b> tab shows who to call (with Call / WhatsApp / Email buttons), other people there, the next action, '
    'the last meeting summary, rapport reminders, company context and policy expiries (\u201c23 days left\u201d, \u201cExpired\u201d, \u201cExpiry unknown\u201d).',
    'Other tabs: <b>Notes</b> (full dated meeting history and all rapport notes), <b>People</b>, <b>Policies</b>.',
    '<b>Add Meeting</b> (blue button) records the next meeting as a new dated entry. Old notes are never overwritten. '
    'If follow-ups are still open, the app asks which ones this meeting took care of.'])
s += [PageBreak()]

# ---- page 5: follow-ups + settings
s += [pair(shot('07_followups', 'Follow-ups: Today, Upcoming, Overdue, Completed'),
           shot('08_settings', 'Settings: reminders, backup, export')),
      Spacer(1, 8), P('Follow-ups, reminders and your data', h2)]
s += steps([
    '<b>Follow-ups</b> tab: tap the circle to mark a follow-up done (Undo is offered). The three-dot menu lets you <b>Reschedule</b> (quick dates), '
    '<b>Snooze until tomorrow</b>, <b>Snooze for a week</b>, edit or delete. Changing or completing a follow-up updates its reminder automatically.',
    'Reminders say only \u201cYou have a follow-up due.\u201d so nothing private shows on a locked screen. If you refuse notification permission, '
    'the app still lists everything that is due.',
    '<b>Mistakes</b>: deleted something by accident? Tap <b>Undo</b> in the message that appears. Saved a client twice? Company page &gt; three-dot menu &gt;'
    '<b>Merge into another company</b>.',
    '<b>Renewals</b>: Home &gt; Upcoming renewals &gt; See all. Filter by line (for example only Medical) and period.'])
s += [P('<b>Protect your data.</b> Your records live <b>only on this phone</b>. If the app is uninstalled or the phone is lost, broken or reset, '
        'they are gone. Go to <b>Settings &gt; Create backup</b> every week and save the file somewhere safe (Google Drive, email to yourself). '
        'To recover or move to a new phone use <b>Restore from backup file</b>. <b>Export to CSV</b> creates spreadsheets for Excel / Google Sheets, '
        'including a renewals worklist; private rapport notes are included only if you tick the box. Backup and CSV files are not password-protected: keep them private.', note),
      Spacer(1, 6), P('BCR (BibinCutRiver)', sig)]

doc.build(s, onFirstPage=footer, onLaterPages=footer)
print('ok')
