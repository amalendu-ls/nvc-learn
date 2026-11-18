#!/bin/bash
# Professional branding for https://learn.nvc.ac.in (Moodle 5.2, theme Boost) -- run in CT 102 as root.
# Re-runnable: overwrites settings, creates categories only if missing.
set -euo pipefail
W=/tmp/nvcbrand; mkdir -p $W
curl -fsS -o $W/nvc-logo.png   https://nvc.ac.in/images/Logo.png
curl -fsS -o $W/nvc-emblem.jpg https://nvc.ac.in/images/Favicon.jpg

cat > $W/hero.html <<'X'
<div class="nvc-hero">
  <h2>Welcome to NVC Learning Portal</h2>
  <p class="lead">The official e-learning platform of Nabadwip Vidyasagar College, Nabadwip &middot; Estd. 1942</p>
  <p class="nvc-hero-buttons">
    <a class="btn btn-warning btn-lg" href="https://learn.nvc.ac.in/login/index.php">Log in</a>
    <a class="btn btn-outline-light btn-lg" href="https://learn.nvc.ac.in/course/index.php">Browse courses</a>
    <a class="btn btn-outline-light btn-lg" href="https://repo.nvc.ac.in">Digital Library</a>
  </p>
</div>
<div class="row nvc-cards">
  <div class="col-md-4"><div class="card h-100"><div class="card-body">
    <h5>For Students</h5>
    <p>Access study materials, submit assignments, attempt quizzes and follow your progress &mdash; anytime, on any device.</p>
  </div></div></div>
  <div class="col-md-4"><div class="card h-100"><div class="card-body">
    <h5>For Teachers</h5>
    <p>Create courses, share lectures and resources, run assessments and communicate with your classes in one place.</p>
  </div></div></div>
  <div class="col-md-4"><div class="card h-100"><div class="card-body">
    <h5>Need help?</h5>
    <p>Log in with the username and password issued by the college. Forgot your password? Use <em>Lost password?</em> on the login page or write to <a href="mailto:moodle-support@example.edu">moodle-support@example.edu</a>.</p>
  </div></div></div>
</div>
X

cat > $W/footer.html <<'X'
<div class="nvc-footer" id="nvc-footer">
  <div><strong>Nabadwip Vidyasagar College</strong> &middot; Nabadwip, Nadia &ndash; 741302, West Bengal</div>
  <div>Affiliated to the University of Kalyani &middot; NAAC Accredited &middot; RUSA Model College</div>
  <div class="nvc-footer-links"><a href="https://nvc.ac.in">College Website</a> &middot; <a href="https://repo.nvc.ac.in">Digital Repository</a> &middot; <a href="mailto:moodle-support@example.edu">Support</a></div>
  <div class="small">&copy; 2026 Nabadwip Vidyasagar College. All rights reserved.</div>
</div>
<script>
document.addEventListener('DOMContentLoaded', function () {
  var f = document.getElementById('nvc-footer');
  var host = document.getElementById('page') || document.getElementById('page-wrapper') || document.body;
  if (f && host) { host.appendChild(f); }
});
</script>
X

cat > $W/nvc.scss <<'X'
$nvc-teal: #116E63;
$nvc-orange: #F39200;
.navbar.fixed-top { border-bottom: 3px solid $nvc-orange; }
.nvc-hero {
  background: linear-gradient(135deg, $nvc-teal 0%, darken($nvc-teal, 12%) 100%);
  color: #fff; border-radius: .75rem; padding: 3rem 1.5rem; margin-bottom: 1.5rem; text-align: center;
  h2 { color: #fff; font-weight: 700; }
  .lead { color: rgba(255, 255, 255, .9); }
  .btn { margin: .25rem; }
}
.nvc-cards .card { border-top: 4px solid $nvc-teal; margin-bottom: 1rem; }
.nvc-cards h5 { color: $nvc-teal; font-weight: 600; }
body#page-login-index { background: linear-gradient(135deg, $nvc-teal 0%, darken($nvc-teal, 15%) 100%); }
#page-login-index .login-container { border-top: 5px solid $nvc-orange; border-radius: .75rem; }
.nvc-footer {
  background: darken($nvc-teal, 15%); color: #e8f3f1; padding: 1.25rem 1rem; text-align: center; font-size: .9rem; line-height: 1.7;
  a { color: #fff; text-decoration: underline; }
}
X

cat > $W/brand.php <<'X'
<?php
define('CLI_SCRIPT', true);
require('/var/www/moodle/config.php');
require_once($CFG->dirroot . '/course/lib.php');
$W = '/tmp/nvcbrand';
$sys = context_system::instance();

// 1. Site identity
$DB->update_record('course', (object)[
    'id' => SITEID,
    'fullname' => 'Nabadwip Vidyasagar College - Learning Portal',
    'shortname' => 'NVC Learn',
    'summary' => '<p>Official e-learning portal of Nabadwip Vidyasagar College, Nabadwip, Nadia (Estd. 1942).</p>',
    'summaryformat' => FORMAT_HTML,
]);
echo "site name set\n";

// 2. Front page: one topic section holding the welcome banner + cards
course_get_format(SITEID)->update_course_format_options(['numsections' => 1]);
course_create_sections_if_missing(SITEID, [0, 1]);
$sec = $DB->get_record('course_sections', ['course' => SITEID, 'section' => 1], '*', MUST_EXIST);
$DB->update_record('course_sections', (object)['id' => $sec->id, 'name' => '',
    'summary' => file_get_contents("$W/hero.html"), 'summaryformat' => FORMAT_HTML]);
rebuild_course_cache(SITEID, true);
echo "front page banner set\n";

// 3. General settings
$cfg = [
    'timezone' => 'Asia/Kolkata', 'country' => 'IN', 'defaultcity' => 'Nabadwip',
    'forcelogin' => 0, 'guestloginbutton' => 0, 'enablemyhome' => 1,
    'frontpage' => '6,4', 'frontpageloggedin' => '5,6,4', 'maxcategorydepth' => 2,
    'defaulthomepage' => 3,
    'custommenuitems' => "College Website|https://nvc.ac.in\nDigital Repository|https://repo.nvc.ac.in\nHelp & Support|mailto:moodle-support@example.edu",
    'auth_instructions' => '<p><strong>Students and teachers:</strong> log in with the username and password issued by Nabadwip Vidyasagar College. New to the portal or cannot log in? Contact <a href="mailto:moodle-support@example.edu">moodle-support@example.edu</a>.</p>',
    'additionalhtmlfooter' => file_get_contents("$W/footer.html"),
    'supportname' => 'NVC Learning Portal Support', 'supportemail' => 'moodle-support@example.edu',
    'noreplyaddress' => 'moodle-support@example.edu',
];
foreach ($cfg as $k => $v) { set_config($k, $v); }
echo "settings set\n";

// 4. Theme colours + custom SCSS
set_config('brandcolor', '#116E63', 'theme_boost');
set_config('scss', file_get_contents("$W/nvc.scss"), 'theme_boost');
echo "theme set\n";

// 5. Logos + favicon
$fs = get_file_storage();
foreach (['logo' => 'nvc-logo.png', 'logocompact' => 'nvc-emblem.jpg', 'favicon' => 'nvc-emblem.jpg'] as $area => $file) {
    $fs->delete_area_files($sys->id, 'core_admin', $area, 0);
    $fs->create_file_from_pathname(['contextid' => $sys->id, 'component' => 'core_admin', 'filearea' => $area,
        'itemid' => 0, 'filepath' => '/', 'filename' => $file], "$W/$file");
    set_config($area, '/' . $file, 'core_admin');
}
echo "logos set\n";

// 6. Course categories (only created if missing)
function nvc_cat($name, $parent, $idnumber, $desc = '') {
    global $DB;
    if ($c = $DB->get_record('course_categories', ['idnumber' => $idnumber])) { return $c->id; }
    return core_course_category::create(['name' => $name, 'parent' => $parent, 'idnumber' => $idnumber,
        'description' => $desc, 'descriptionformat' => FORMAT_HTML])->id;
}
$ug = nvc_cat('Undergraduate (UG)', 0, 'UG', '<p>Honours and general undergraduate programmes.</p>');
foreach (['Bengali', 'Botany', 'Chemistry', 'Commerce', 'Computer Science', 'Economics', 'Education', 'English',
          'Geography', 'History', 'Mathematics', 'Philosophy', 'Physical Education', 'Physics', 'Political Science',
          'Sanskrit', 'Zoology'] as $d) {
    nvc_cat($d, $ug, 'UG-' . strtoupper(str_replace(' ', '-', $d)));
}
$pg = nvc_cat('Postgraduate (PG)', 0, 'PG', '<p>Postgraduate programmes.</p>');
nvc_cat('Sanskrit', $pg, 'PG-SANSKRIT');
$dl = nvc_cat('Distance Education (DODL)', 0, 'DODL', '<p>M.A. programmes in Distance/Online (DODL) mode.</p>');
foreach (['Bengali', 'English', 'History', 'Education'] as $d) {
    nvc_cat($d, $dl, 'DODL-' . strtoupper($d));
}
if ($c = $DB->get_record('course_categories', ['id' => 1, 'name' => 'Category 1'])) {
    core_course_category::get(1)->update(['name' => 'General & Orientation', 'idnumber' => 'GEN']);
}
echo "categories: " . $DB->count_records('course_categories') . "\n";

// 7. Apply
theme_reset_all_caches();
purge_all_caches();
echo "BRANDING-DONE\n";
X

chown -R www-data:www-data $W
runuser -u www-data -- php $W/brand.php
