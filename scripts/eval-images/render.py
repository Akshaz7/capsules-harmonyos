# Renders 10 synthetic test photos (text on paper/whiteboard backgrounds) for the T5-4 vision eval.
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import random
random.seed(7)
F = '/System/Library/Fonts/Supplemental/'
def font(name, size):
    return ImageFont.truetype(F + name, size)
IMAGES = {
 'receipt': ('Courier New.ttf', (250,248,240), (30,30,30), [
   'CAFE LUNA', 'Table 4', '', '2 x Cappuccino    9.00 zl', '1 x Pierogi       24.50 zl', '1 x Soup          16.00 zl',
   '1 x Cheesecake    15.00 zl', '', 'TOTAL            64.50 zl', '', 'Thank you!']),
 'restaurant_bill': ('Courier New.ttf', (255,255,250), (20,20,20), [
   'TRATTORIA ROMA', '', 'Pizza Margherita   €12.00', 'Lasagne            €14.50', 'Tiramisu x2        €13.00',
   'Wine (bottle)      €28.00', '', 'Total              €67.50', 'Split between 4 people']),
 'recipe': ('Georgia.ttf', (255,250,235), (60,30,10), [
   'Tomato Pasta', '', '1. Boil the pasta for 9 minutes.', '2. Simmer the sauce for 15 minutes.',
   '3. Bake with cheese for 10 minutes.', '4. Rest for 2 minutes, then serve.']),
 'whiteboard_todo': ('Chalkduster.ttf', (245,245,245), (20,40,160), [
   'TODO this week:', '- email Anna', '- book dentist', '- fix bike', '- pay rent']),
 'shopping_list': ('Bradley Hand Bold.ttf', (255,255,200), (20,20,20), [
   'Shopping', '- milk', '- eggs', '- bread', '- apples', '- coffee']),
 'workout': ('Arial Bold.ttf', (235,240,255), (10,10,60), [
   'LEG DAY WORKOUT', '', '- 3x12 squats', '- 3x10 lunges', '- plank 60 seconds', '- 20 burpees', '- rest 90 seconds']),
 'timetable': ('Arial.ttf', (255,255,255), (0,0,0), [
   'Class timetable', '', 'Mon 9:00  Maths', 'Tue 10:00  Physics', 'Wed 9:00  English', 'Thu 11:00  Chemistry',
   'Fri 8:00  History']),
 'medicine': ('Arial Bold.ttf', (255,255,255), (0,0,90), [
   'IBUPROFEN 200 mg', '', 'Take 1 tablet', 'every 8 hours', 'with food.', 'Max 3 tablets a day.']),
 'scoreboard': ('Chalkduster.ttf', (30,60,40), (240,240,240), [
   'Ping pong', '', 'Tom  vs  Ana', 'first to 11']),
 'sticky_note': ('Bradley Hand Bold.ttf', (255,240,120), (40,40,40), [
   'Water the plants', 'every 3 days!']),
}
for name, (fname, bg, fg, lines) in IMAGES.items():
    size = 46 if len(lines) < 7 else 38
    f = font(fname, size); tf = font(fname, int(size*1.25))
    W, H = 900, 140 + len(lines) * int(size*1.6)
    img = Image.new('RGB', (W, H), bg); d = ImageDraw.Draw(img)
    y = 60
    for i, line in enumerate(lines):
        d.text((60 + random.randint(-4,4), y), line, fill=fg, font=tf if i == 0 else f)
        y += int(size*1.6)
    img = img.rotate(random.uniform(-2.5, 2.5), expand=True, fillcolor=(90,85,80)).filter(ImageFilter.GaussianBlur(0.6))
    img.save(name + '.jpg', quality=85)
    print(name, img.size)
