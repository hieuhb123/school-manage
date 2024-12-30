import express from "express";
import bodyParser from "body-parser";
import pg from "pg";
import session from "express-session";


const app = express();
const port = 3000;

const db = new pg.Client({
  user: "postgres",
  host: "localhost",
  database: "school manage",
  password: "admin",
  port: 5432,
});
// const db = new pg.Client({
//   user: "postgres",
//   host: "26.131.209.50",
//   database: "HUST",
//   password: "admin",
//   port: 5432,
// });

db.connect();

app.use(express.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.static("public"));

app.use(session({
  secret: 'secret-key',
  resave: false,
  saveUninitialized: true,
}));

let curPage = 'Home';
var toDay = new Date().toJSON().split("T")[0];
toDay = '2024-01-02';
const getSemester_id = (await db.query("SELECT getSemester($1);", [toDay])).rows[0].getsemester;
console.log(getSemester_id);
app.get("/", (req, res) => {
  curPage = 'Home';
  if(!req.session.user)
    res.render("home.ejs", {
      currentPage: curPage
    });
  else 
    res.render("home.ejs", {
      currentPage: curPage,
      user: req.session.user
    });
});

app.get("/service", (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    res.render("home.ejs", {
      currentPage: curPage,
      user: req.session.user
    });
  }
});

app.get("/student/profile", async (req, res) => {
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = '';
    let get_tutor = await db.query("SELECT * FROM tutor WHERE tutor_id = $1", [req.session.user.student_id]);
    let get_CPA = await db.query(" \
      SELECT SUM(credit) AS cumulative_credits, ROUND((SUM(credit * four_scale) / SUM(credit)), 2) AS CPA \
      FROM subject_grades_of_students \
      WHERE student_id = $1 AND semester_id <= $2;", [req.session.user.student_id, getSemester_id]);
    let get_GPA = await db.query(" \
      SELECT semester_id, gpa \
      FROM calculate_gpa \
      WHERE student_id = $1 \
      ORDER BY semester_id;", [req.session.user.student_id]);
    let get_conduct_point = await db.query(" \
      SELECT semester_id, formteacher_name, conduct_point \
      FROM give_conduct_point \
      JOIN form_teacher USING (formteacher_id) \
      WHERE student_id = $1 \
      ORDER BY semester_id;", [req.session.user.student_id]);
    let get_headmaster = await db.query(" \
      SELECT formteacher_name \
      FROM give_conduct_point \
      JOIN form_teacher f USING (formteacher_id) \
      WHERE student_id = $1 AND semester_id = $2;", [req.session.user.student_id, getSemester_id]);
    let get_institute = await db.query(" \
      SELECT institute_name \
      FROM student \
      JOIN institute USING (institute_id) \
      WHERE student_id = $1;", [req.session.user.student_id]);
    res.render("student/profile.ejs", {
      currentPage: curPage,
      user: req.session.user,
      tutor: get_tutor.rows[0],
      cpain: get_CPA.rows[0],
      grade: Math.floor(Number(getSemester_id)/10 - Number(req.session.user.student_id)/10000),
      GPA: get_GPA.rows,
      conduct: get_conduct_point.rows,
      manager_class: get_headmaster.rows[0],
      institute: get_institute.rows[0].institute_name
    });
  }
});

app.get("/student/result", async (req, res) => {
  
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = 'Service';
    const getResult = await db.query("\
      SELECT semester_id, t1.subject_id, subject_name, t1.credit, class_point, four_scale, alphabet_point \
      FROM subject_grades_of_students t1 \
      JOIN subject USING (subject_id) \
      WHERE student_id = $1 AND semester_id < $2 \
      ORDER BY semester_id;", [req.session.user.student_id, getSemester_id]);
    res.render("student/result.ejs", {
      currentPage: curPage,
      user: req.session.user,
      result: getResult.rows
    });
  }
});
app.get("/student/register-class", async (req, res) => {
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = 'Service';
    const getClassRegised = await db.query(" \
      SELECT ci.clazz_id, ci.subject_name, subject_id, 'Thành công' AS status, credit, room, start_time, finish_time, dow \
      FROM enroll e \
      JOIN class_information ci USING (clazz_id, semester_id) \
      JOIN subject USING(subject_id) \
      WHERE student_id = $1 AND semester_id = $2 \
      ORDER BY dow, start_time;", [req.session.user.student_id, getNextSemester(getSemester_id)]);
    res.render("student/register-class.ejs", {
      currentPage: curPage,
      user: req.session.user,
      semester: getNextSemester(getSemester_id),
      class_rg: getClassRegised.rows
    });
  }
});

app.get("/student/register-class/class-open", async (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    const getClassopen = await db.query(" \
      SELECT ci.clazz_id, ci.subject_id, s.subject_name, current_student_number, max_student, dow, room, start_time, finish_time \
      FROM class_information ci \
      JOIN subject s USING (subject_id) \
      WHERE semester_id = $1;", [getNextSemester(getSemester_id)]);
    res.render("student/class-open.ejs", {
      currentPage: curPage,
      user: req.session.user,
      class_open: getClassopen.rows
    });
  }
});

app.get("/student/schedule", async(req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    const getSchedule = await db.query("\
      SELECT dow, start_time, finish_time, room, ci.clazz_id, ci.subject_id, s.subject_name \
      FROM enroll e \
      JOIN class_information ci USING (clazz_id, semester_id) \
      JOIN subject s USING (subject_id) \
      WHERE student_id = $1 AND semester_id = $2 \
      ORDER BY dow, start_time;", [req.session.user.student_id, getSemester_id]);
    res.render("student/schedule.ejs", {
      currentPage: curPage,
      user: req.session.user,
      schedule: getSchedule.rows
    });
  }
});

app.get("/teacher/profile", async (req, res) => {
  
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = '';
    const getTeacherInfo = await db.query("\
      SELECT lecturer_id, lecturer_name, gender, phone_number, institute_name \
      FROM lecturer \
      JOIN institute USING (institute_id) \
      WHERE lecturer_id = $1;", [req.session.user.lecturer_id]);
    res.render("teacher/profile.ejs", {
      currentPage: curPage,
      user: req.session.user,
      info: getTeacherInfo.rows[0]
    });
  }
});

app.get("/teacher/schedule", async (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    const getSchedule = await db.query("\
      SELECT clazz_id, subject_id, subject_name, dow, start_time, finish_time, room \
      FROM class_information \
      WHERE lecturer_id = $1 AND semester_id = $2 \
      ORDER BY dow, start_time;", [req.session.user.lecturer_id, getSemester_id]);
    res.render("teacher/schedule.ejs", {
      currentPage: curPage,
      user: req.session.user,
      schedule: getSchedule.rows
    });
  }
});

app.get("/teacher/give_point", async (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    const getClass = await db.query("\
      SELECT clazz_id \
      FROM class_information \
      WHERE lecturer_id = $1 AND semester_id = $2;", [req.session.user.lecturer_id, getSemester_id]);
    res.render("teacher/point.ejs", {
      currentPage: curPage,
      user: req.session.user,
      semester: getSemester_id,
      class_teach: getClass.rows 
    });
  }
});

app.get("/tutor/profile", async (req, res) => {
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = '';
    let get_tutor = await db.query("SELECT * FROM tutor WHERE tutor_id = $1", [req.session.user.student_id]);
    let get_CPA = await db.query(" \
      SELECT SUM(credit) AS cumulative_credits, ROUND((SUM(credit * four_scale) / SUM(credit)), 2) AS CPA \
      FROM subject_grades_of_students \
      WHERE student_id = $1 AND semester_id < $2;", [req.session.user.student_id, getSemester_id]);
    let get_GPA = await db.query(" \
      SELECT semester_id, gpa \
      FROM calculate_gpa \
      WHERE student_id = $1;", [req.session.user.student_id]);
    let get_conduct_point = await db.query(" \
      SELECT semester_id, formteacher_name, conduct_point \
      FROM give_conduct_point \
      JOIN form_teacher USING (formteacher_id) \
      WHERE student_id = $1;", [req.session.user.student_id]);
    let get_headmaster = await db.query(" \
      SELECT formteacher_name \
      FROM give_conduct_point \
      JOIN form_teacher f USING (formteacher_id) \
      WHERE student_id = $1 AND semester_id = $2;", [req.session.user.student_id, getSemester_id]);
    let get_institute = await db.query(" \
      SELECT institute_name \
      FROM student \
      JOIN institute USING (institute_id) \
      WHERE student_id = $1;", [req.session.user.student_id]);
    res.render("student/profile.ejs", {
      currentPage: curPage,
      user: req.session.user,
      tutor: get_tutor.rows[0],
      cpain: get_CPA.rows[0],
      grade: Math.floor(Number(getSemester_id)/10 - Number(req.session.user.student_id)/10000),
      GPA: get_GPA.rows,
      conduct: get_conduct_point.rows,
      manager_class: get_headmaster.rows[0],
      institute: get_institute.rows[0].institute_name
    });
  }
});

app.get("/tutor/result", async (req, res) => {
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = 'Service';
    const getResult = await db.query("\
      SELECT semester_id, t1.subject_id, subject_name, t1.credit, class_point, four_scale, alphabet_point \
      FROM subject_grades_of_students t1 \
      JOIN subject USING (subject_id) \
      WHERE student_id = $1 AND semester_id < $2;", [req.session.user.student_id, getSemester_id]);
    res.render("student/result.ejs", {
      currentPage: curPage,
      user: req.session.user,
      result: getResult.rows
    });
  }
});

app.get("/form_teacher/give_point", async (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    const getStudentInfo = await db.query("\
      SELECT s.student_id, student_name, conduct_point \
      FROM give_conduct_point \
      JOIN student s USING (student_id) \
      WHERE formteacher_id = $1 AND semester_id = $2;", [req.session.user.formteacher_id, getSemester_id]);
    res.render("form_teacher/point.ejs", {
      currentPage: curPage,
      user: req.session.user,
      student: getStudentInfo.rows 
    });
  }
});

app.get("/form_teacher/profile", async (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = '';
    const getTeacherInfo = await db.query("\
      SELECT institute_name \
      FROM form_teacher \
      JOIN institute USING (institute_id) \
      WHERE formteacher_id = $1;", [req.session.user.formteacher_id]);
    res.render("form_teacher/profile.ejs", {
      currentPage: curPage,
      user: req.session.user,
      institute: getTeacherInfo.rows[0]
    });
  }
});

app.get("/head_master/profile", async (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = '';
    const getInfo = await db.query("\
      SELECT institute_name \
      FROM headmaster \
      JOIN institute USING (institute_id) \
      WHERE headmaster_id = $1;", [req.session.user.headmaster_id]);
    res.render("head_master/profile.ejs", {
      currentPage: curPage,
      user: req.session.user,
      institute: getInfo.rows[0]
    });
  }
});

app.get("/head_master/addSC", async (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    const getInstitute = await db.query("\
      SELECT * \
      FROM institute \
      WHERE institute_id = $1", [req.session.user.institute_id]);
    const getSub = await db.query("\
      SELECT * \
      FROM subject \
      WHERE institute_id = $1 \
      ORDER BY subject_id ASC ", [req.session.user.institute_id]);
    let getClass = await db.query("\
        SELECT c.clazz_id, c.subject_id \
        FROM clazz c\
        JOIN subject USING(subject_id)\
        WHERE institute_id = $1 \
        ORDER BY subject_id ASC ", [req.session.user.institute_id]);
    res.render("head_master/addSub-Class.ejs", {
      currentPage: curPage,
      user: req.session.user,
      institute: getInstitute.rows[0],
      curSub: getSub.rows,
      curClass: getClass.rows
    });
  }
});

app.get("/head_master/addCNS", async (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    const getSub = await db.query("\
      SELECT s.subject_id, s.subject_name \
      FROM subject s\
      WHERE institute_id = $1 \
      ORDER BY subject_id ASC ", [req.session.user.institute_id]);
    for(let i = 0; i < getSub.rows.length ; i++) {
      const getClass = await db.query("\
        SELECT clazz_id \
        FROM clazz \
        WHERE subject_id = $1;", [getSub.rows[i].subject_id]);
      getSub.rows[i].clazz = getClass.rows;
    }
    res.render("head_master/addCNS.ejs", {
      currentPage: curPage,
      user: req.session.user,
      semester: getNextSemester(getSemester_id),
      subInfo: getSub.rows
    });
  }
});

app.get("/admin/addSemester", async (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    const getSes = await db.query("\
      SELECT * \
      FROM semester s \
      ORDER BY semester_id ASC");
    res.render("admin/semester.ejs", {
      currentPage: curPage,
      user: req.session.user,
      ses: getSes.rows
    });
  }
});

app.get("/login", (req, res) => {
  res.render("login.ejs");
});

app.get('/logout', (req, res) => {
  req.session.destroy(err => {
    if (err) {
      return res.send('Error logging out');
    }
    res.redirect('/');
  });
});

app.post("/login", async (req, res) => {
    const username = req.body.username;
    const password = req.body.password;
    const typeLogin = req.body.listGroupRadios;
    let user_data;
    if(typeLogin == 'admin') {
      if(username == 'admin') {
        if(password == 'admin') {
          user_data = {typeLogin: typeLogin};
          req.session.user = user_data;
          res.redirect("/");
        }
        else {
          res.render("login.ejs", {status: 'Incorrect Password'});
        }
      }
      else {
        res.render("login.ejs", {status: 'User not found'});
      }
    }
    else try {
      let getUsername;
      if(typeLogin === 'sv') getUsername = await db.query("SELECT * FROM student WHERE username = $1", [username]);
      else if(typeLogin == 'gv') getUsername = await db.query("SELECT * FROM lecturer WHERE username = $1", [username]);
      else if(typeLogin == 'ph') getUsername = await db.query("SELECT * FROM student WHERE student_id = $1", [username]);
      else if(typeLogin == 'cn') getUsername = await db.query("SELECT * FROM form_teacher WHERE username = $1", [username]);
      else if(typeLogin == 'ht') getUsername = await db.query("SELECT * FROM headmaster WHERE username = $1", [username]);

      if (getUsername.rows.length > 0) {
        if(typeLogin === 'ph' && password === getUsername.rows[0].citizen_id){
          user_data = getUsername.rows[0];
          user_data.typeLogin = typeLogin;
          console.log(user_data);
          req.session.user = user_data;
          res.redirect("/");
        }
        else if (typeLogin != 'ph' && password === getUsername.rows[0].pword) {
          user_data = getUsername.rows[0];
          user_data.typeLogin = typeLogin;
          console.log(user_data);
          req.session.user = user_data;
          res.redirect("/");
        } else {
          res.render("login.ejs", {status: 'Incorrect Password'});
        }
      } else {
        res.render("login.ejs", {status: 'User not found'});
      }
    } catch (err) {
      console.log(err);
    }
});

app.post("/student/submitRegister", async (req, res) => {
  let res_delete = [], res_insert = [];
  for(let i = 0 ; i < req.body.length ; i++) {
    if(req.body[i].status == 'Delete') {
      const sql = await db.query(" \
        DELETE FROM enroll \
        WHERE student_id = $1 AND semester_id = $2 AND clazz_id = $3 RETURNING *", 
      [req.session.user.student_id, getNextSemester(getSemester_id), req.body[i].class_id]);
      if(sql.rows[0] != null)
        res_delete.push(sql.rows[0].clazz_id);
    }

    if(req.body[i].status == 'Insert') {
        const sql = await db.query(" \
        INSERT INTO enroll(student_id, semester_id, clazz_id) VALUES \
        ($1, $2, $3) RETURNING *", 
      [req.session.user.student_id, getNextSemester(getSemester_id), req.body[i].class_id]); 
      if(sql.rows[0] != null)
        res_insert.push(sql.rows[0].clazz_id);
    }
  }
  res.json({ delete_info: res_delete, insert_info: res_insert});
});

app.post("/student/getClass", async (req, res) => {
  try {
    const getClassRegised = await db.query(" \
      SELECT ci.clazz_id, ci.subject_name, subject_id, 'Insert' AS status, credit, room, start_time, finish_time, dow \
      FROM class_information ci \
      JOIN subject USING(subject_id) \
      WHERE ci.clazz_id = $1 AND semester_id = $2", [req.body.class_id, getNextSemester(getSemester_id)]);
    res.json({message: "Đã thêm", data: getClassRegised.rows[0]});
  }
  catch (err) {
    res.json({message: err.message});
  }
});

app.post("/teacher/get_class_give_point", async (req, res) => {
  try {
    const getClassInfo = await db.query(" \
      SELECT clazz_id, subject_id, subject_name, current_student_number \
      FROM class_information \
      WHERE semester_id = $1 AND clazz_id = $2;", [getSemester_id, req.body.class_id]);
    const getStudentInfo = await db.query(" \
      SELECT s.student_name, s.student_id, midpoint, finalpoint \
      FROM class_information ci \
      JOIN enroll e USING (clazz_id) \
      JOIN student s USING (student_id) \
      WHERE lecturer_id = $1 AND e.semester_id = $2 AND clazz_id = $3;", [req.session.user.lecturer_id, getSemester_id, req.body.class_id]);
    res.json({
      class_info: getClassInfo.rows[0], 
      student_info: getStudentInfo.rows});
  }
  catch(err) {
    console.log(err);
  }
});

app.post("/teacher/give_point", async (req, res) => {
  try {
    for(let i = 0 ; i < req.body.class_regiter.length ; i++) {
      const formdata = [req.body.class_regiter[i].student_id, req.body.class_id, getSemester_id, req.body.class_regiter[i]. midpoint, req.body.class_regiter[i].finalpoint];
      await db.query(" \
        UPDATE enroll \
        SET midpoint = $4, finalpoint = $5 \
        WHERE student_id = $1 AND clazz_id = $2 AND semester_id = $3;", formdata);
    }
    res.json({ message: 'Cập nhật thành công'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
  
});

app.post("/form_teacher/give_point", async (req, res) => {
  try {
    for(let i = 0 ; i < req.body.update_conduct.length ; i++) {
      const formdata = [req.body.update_conduct[i].student_id, getSemester_id, req.body.update_conduct[i].conduct_point];
      await db.query(" \
        UPDATE give_conduct_point \
        SET conduct_point = $3 \
        WHERE student_id = $1 AND semester_id = $2;", formdata);
    }
    res.json({ message: 'Cập nhật thành công'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
});

app.post("/head_master/insertSub", async (req, res) => {
  try {
    await db.query(" \
      INSERT INTO subject(subject_id, subject_name, credit, institute_id, final_coefficient) \
      VALUES ($1, $2, $3, $4, $5);", [req.body.subject_id, req.body.subject_name, req.body.credit, req.session.user.institute_id, req.body.final_coefficient]);
    res.json({ message: 'Cập nhật thành công'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
  
});

app.post("/head_master/insertClass", async (req, res) => {
  try {
    await db.query(" \
      INSERT INTO clazz(clazz_id, subject_id) \
      VALUES ($1, $2);", [req.body.clazz_id, req.body.subject_id]);
    res.json({ message: 'Cập nhật thành công'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
  
});

app.post("/head_master/get_class", async (req, res) => {
  try {
    const get_teach_info = await db.query(" \
      SELECT * \
      FROM teach \
      WHERE clazz_id = $1 AND semester_id = $2;", [req.body.class_id, getNextSemester(getSemester_id)]);
    if(get_teach_info.rows.length > 0) {
      const get_time = await db.query(" \
        SELECT dow, start_time, finish_time \
        FROM class_information \
        WHERE clazz_id = $1 AND semester_id = $2;", [req.body.class_id, getNextSemester(getSemester_id)]);
      res.json({ typeInfo: 'have_Teach', teach: get_teach_info.rows[0], time: get_time.rows});
    }
    else
      res.json({typeInfo: 'nothave_Teach'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
  
});

app.post("/head_master/insert_Teach", async (req, res) => {
  try {
    await db.query(" \
      INSERT INTO teach(clazz_id, semester_id, lecturer_id, room, max_student) \
      VALUES ($1, $2, $3, $4, $5);", [req.body.clazz_id, getNextSemester(getSemester_id), req.body.lecturer_id, req.body.room, req.body.max_student]);
    res.json({ message: 'Thêm thành công'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
  
});
app.post("/head_master/delete_Teach", async (req, res) => {
  try {              
    await db.query(" \
      DELETE FROM teach \
      WHERE clazz_id = $1 AND semester_id = $2;", [req.body.clazz_id, getNextSemester(getSemester_id)]);
    res.json({ message: 'Xóa thành công'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
});
app.post("/head_master/insert_Time", async (req, res) => {
  try {
    await db.query(" \
      INSERT INTO class_information(clazz_id, semester_id, dow, start_time, finish_time) \
      VALUES ($1, $2, $3, $4, $5);", [req.body.clazz_id, getNextSemester(getSemester_id), req.body.dow, req.body.start_time, req.body.finish_time]);
    res.json({ message: 'Thêm thành công'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
});
app.post("/head_master/delete_Time", async (req, res) => {
  try {              
    await db.query(" \
      DELETE FROM study_time \
      WHERE clazz_id = $1 AND semester_id = $2 AND dow = $3 AND start_time = $4 AND finish_time = $5;", [req.body.clazz_id, getNextSemester(getSemester_id), req.body.dow, req.body.start_time, req.body.finish_time]);
    res.json({ message: 'Xóa thành công'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
});
app.post("/admin/insert-semester", async (req, res) => {
  try {
    await db.query(" \
      INSERT INTO semester(semester_id, start_enroll_time, finish_enroll_time, start_givepoint_time, finish_givepoint_time, start_semester_date, finish_semester_date) \
      VALUES ($1, $2, $3, $4, $5, $6, $7);", [req.body.semester_id, req.body.start_enroll_time, req.body.finish_enroll_time, req.body.start_givepoint_time, req.body.finish_givepoint_time, req.body.start_semester_date, req.body.finish_semester_date]);
    res.json({ message: 'Cập nhật thành công'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
  
});

app.post("/admin/delete-semester", async (req, res) => {
  try {
    await db.query(" \
      DELETE FROM semester \
      WHERE semester_id = $1;", [req.body.semester_id]);
    res.json({ message: 'Deleted'});
  }
  catch (err) {
    res.json({ message: err.message});
  }
  
});

function getNextSemester(semester_id) {
  const year = semester_id.slice(0, 4); 
  const semester = parseInt(semester_id.slice(4, 5)); 

  if (semester === 1) {
    return year + '2';  
  } else if (semester === 2) {
    const nextYear = parseInt(year) + 1;  
    return nextYear + '1'; 
  }
};


app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});