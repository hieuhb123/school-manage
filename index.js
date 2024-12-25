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

app.get("/student/result", async (req, res) => {
  
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
      WHERE student_id = $1 AND semester_id = $2;", [req.session.user.student_id, getNextSemester(getSemester_id)]);
    res.render("student/register-class.ejs", {
      currentPage: curPage,
      user: req.session.user,
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
      WHERE student_id = $1 AND semester_id = $2;", [req.session.user.student_id, getSemester_id]);
    res.render("student/schedule.ejs", {
      currentPage: curPage,
      user: req.session.user,
      schedule: getSchedule.rows
    });
  }
});

app.get("/teacher/profile", (req, res) => {
  
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = '';
    res.render("teacher/profile.ejs", {
      currentPage: curPage,
      user: req.session.user
    });
  }
});

app.get("/teacher/schedule", async (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    const getSchedule = await db.query("\
      SELECT clazz_id, s.subject_id, s.subject_name, dow, start_time, finish_time, room \
      FROM class_information \
      JOIN subject s USING (subject_id) \
      WHERE lecturer_id = $1 AND semester_id = $2;", [req.session.user.lecturer_id, getSemester_id]);
    res.render("teacher/schedule.ejs", {
      currentPage: curPage,
      user: req.session.user,
      schedule: getSchedule.rows
    });
  }
});

app.get("/teacher/give_point", (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    res.render("teacher/point.ejs", {
      currentPage: curPage,
      user: req.session.user
    });
  }
});

app.get("/teacher/register-class", (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    res.render("teacher/class.ejs", {
      currentPage: curPage,
      user: req.session.user
    });
  }
});

app.get("/turtor/profile", (req, res) => {
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = '';
    res.render("tutor/profile.ejs", {
      currentPage: curPage,
      user: req.session.user
    });
  }
});

app.get("/turtor/result", (req, res) => {
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = 'Service';
    res.render("tutor/result.ejs", {
      currentPage: curPage,
      user: req.session.user
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
    try {
      let getUsername;
      if(typeLogin === 'sv') getUsername = await db.query("SELECT * FROM student WHERE username = $1", [username]);
      else if(typeLogin == 'gv') getUsername = await db.query("SELECT * FROM lecturer WHERE username = $1", [username]);
      else getUsername = await db.query("SELECT * FROM student WHERE student_id = $1", [username]);

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
  const getClassRegised = await db.query(" \
    SELECT ci.clazz_id, ci.subject_name, subject_id, 'Insert' AS status, credit, room, start_time, finish_time, dow \
    FROM class_information ci \
    JOIN subject USING(subject_id) \
    WHERE ci.clazz_id = $1 AND semester_id = $2", [req.body.class_id, getNextSemester(getSemester_id)]);
  res.json(getClassRegised.rows[0]);
});

app.post("/teacher/give_point", (req, res) => {
  const earn_req = req.body;
  res.json({ message: 'Dữ liệu đã nhận', data: earn_req});
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
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
}