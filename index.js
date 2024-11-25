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

app.get("/student/profile", (req, res) => {
  
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = '';
    res.render("student/profile.ejs", {
      currentPage: curPage,
      user: req.session.user
    });
  }
});

app.get("/student/result", (req, res) => {
  
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = 'Service';
    res.render("student/result.ejs", {
      currentPage: curPage,
      user: req.session.user
    });
  }
});
app.get("/student/register-class", (req, res) => {
  
  if(!req.session.user)
    res.redirect("/");
  else {
    curPage = 'Service';
    res.render("student/register-class.ejs", {
      currentPage: curPage,
      user: req.session.user
    });
  }
});

app.get("/student/register-class/class-open", (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    res.render("student/class-open.ejs", {
      currentPage: curPage,
      user: req.session.user
    });
  }
});

app.get("/student/schedule", async(req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    const getSchedule = await db.query("SELECT * FROM student WHERE username = $1", [req.session.user.student_id]);
    res.render("student/schedule.ejs", {
      currentPage: curPage,
      user: req.session.user
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

app.get("/teacher/schedule", (req, res) => {
  if(!req.session.user)
      res.redirect("/");
  else {
    curPage = 'Service';
    res.render("teacher/schedule.ejs", {
      currentPage: curPage,
      user: req.session.user
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
      if(typeLogin == 'sv') getUsername = await db.query("SELECT * FROM student WHERE username = $1", [username]);
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

app.post("/student/submitRegister", (req, res) => {
  const earn_req = req.body;
  res.json({ message: 'Dữ liệu đã nhận', data: earn_req});
});

app.post("/teacher/give_point", (req, res) => {
  const earn_req = req.body;
  res.json({ message: 'Dữ liệu đã nhận', data: earn_req});
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});

