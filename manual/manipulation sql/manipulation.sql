--------------STUDENT---------------------------------
-- Thời khóa biểu của sinh viên
-- input: student_id, semester_id
-- Các trường: mã lớp, mã học phần, tên học phần, thứ, thời gian, phòng học
SELECT ci.clazz_id, ci.subject_id, subject_name, dow, start_time, finish_time, room
FROM enroll e
JOIN class_information ci USING (clazz_id, semester_id)
JOIN subject s USING (subject_id)
WHERE student_id = $1 AND semester_id = $2
ORDER BY dow, start_time;

-- Bảng điểm của học sinh
-- input: student_id
-- Các trường: semester, subject_id (mã học phần), tên học phần, tín chỉ, điểm học phần hệ 10, hệ 4 và điểm chữ
SELECT semester_id, t1.subject_id, subject_name, t1.credit, class_point, four_scale, alphabet_point
FROM subject_grades_of_students t1
JOIN subject USING (subject_id)
WHERE student_id = $1
ORDER BY semester_id;

-- Bảng đăng kí lớp trong kì hiện tại (ở chức năng đăng kí tín chỉ)
-- input: student, semester
-- Các trường: mã lớp, mã học phần, trạng thái đăng kí, tín chỉ, địa điểm học, thời gian học
SELECT DISTINCT ci.clazz_id, subject_id, 'Thành công' AS status, room, start_time, finish_time
FROM enroll e
JOIN class_information ci USING (clazz_id, semester_id)
WHERE student_id = $1 AND semester_id = $2
ORDER BY dow, start_time;

-- Thêm một lớp vào bảng đăng kí học phần
-- input: clazz_id, semester_id, student_id
INSERT INTO enroll(student_id, semester_id, clazz_id) VALUES
($1, $2, $3);

-- Xóa một lớp khỏi bảng đăng kí học phần
-- input: clazz_id, semester_id, student_id
DELETE FROM enroll
WHERE student_id = $1 AND semester_id = $2 AND clazz_id = $3;

-- Danh sách các lớp mở
-- input: semester_id
-- Các trường: mã lớp, mã học phần, tên học phần, số lượng đăng kí hiện tại và tối đa, thứ, phòng học, thời gian
SELECT ci.clazz_id, ci.subject_id, s.subject_name, current_student_number, max_student, dow, room, start_time, finish_time
FROM class_information ci
JOIN subject s USING (subject_id)
WHERE semester_id = $1;

-- Lấy thông tin sinh viên (chia làm 3 câu lệnh)
--(1)
-- student_id, citizen_id, name, gender, ngày sinh, ngành, viện quản lí, email,
-- tên cha mẹ, ngày sinh, nghề nghiệp, số điện thoại
-- input: student_id
SELECT student_id, citizen_id, student_name, gender, dob, major, institute_name, username
FROM student
JOIN institute USING (institute_id)
WHERE student_id = $1;

-- (2)
-- tên GVCN (ở kì hiện tại)
-- input: student_id, semester_id
SELECT formteacher_name
FROM give_conduct_point
JOIN form_teacher f USING (formteacher_id)
WHERE student_id = $1 AND semester_id = $2;

-- (3)
-- CPA, tín chỉ tích lũy
-- input: student_id, semester_id
SELECT SUM(credit) AS cumulative_credits, (SUM(credit * four_scale) / SUM(credit)) AS CPA
FROM subject_grades_of_students
WHERE student_id = $1 AND semester_id < $2;

-- Thông tin về điểm rèn luyện qua các kỳ + tên gvcn của kỳ đó
-- input: student_id
SELECT semester_id, formteacher_name, conduct_point
FROM give_conduct_point
JOIN form_teacher USING (formteacher_id)
WHERE student_id = $1
ORDER BY semester_id;

-- Xem thông tin giáo viên chủ nhiệm kỳ hiện tại
-- input: student_id, semester
SELECT formteacher_id, formteacher_name, gender, phone_number
FROM give_conduct_point
JOIN form_teacher USING (formteacher_id)
WHERE student_id = $1 AND semester_id = $2;

-- Xem điểm các lớp của một kỳ nào đó
-- input: student_id, semester_id
SELECT clazz_id, subject_id, subject_name, class_point, alphabet_point
FROM calculate_grade_in_each_class
JOIN subject USING (subject_id)
WHERE student_id = $1 AND semester_id = $2;

-- Xem GPA qua các kỳ
-- input: student_id
SELECT semester_id, gpa
FROM calculate_gpa
WHERE student_id = $1
ORDER BY semester_id;

-- Chỉnh sửa thông tin cá nhân

-- Xem thông tin cá nhân của lecturer
-- input: class_id, semester_id
SELECT lecturer_id, lecturer_name, gender, phone_number
FROM teach
JOIN lecturer USING (lecturer_id)
WHERE clazz_id = $1 AND semester_id = $2;

---------------------LECTURER------------------------
-- Xem thông tin cá nhân của mình
-- input: lecturer_id
SELECT lecturer_id, lecturer_name, gender, phone_number, institute_name
FROM lecturer
JOIN institute USING (institute_id)
WHERE lecturer_id = $1;

-- Lấy thời khóa biểu của giáo viên theo kì (liệt kê các class trong 1 kỳ)
-- input: lecturer_id, semester_id
SELECT clazz_id, s.subject_id, subject_name, dow, start_time, finish_time, room
FROM class_information
JOIN subject s USING (subject_id)
WHERE lecturer_id = $1 AND semester_id = $2
ORDER BY semester_id;

-- Xem điểm các sinh viên của một lớp mà mình phụ trách
-- Step (1): hiện danh sách các lớp theo kỳ
-- input: lecturer_id, semester_id
SELECT clazz_id, s.subject_id, subject_name
FROM class_information
JOIN subject s USING (subject_id)
WHERE lecturer_id = $1 AND semester_id = $2;

SELECT te.clazz_id, cl.subject_id, subject_name
FROM teach te
JOIN clazz cl USING (clazz_id)
JOIN subject USING (subject_id)
WHERE lecturer_id = $1 AND semester_id = $2;
-- Step (2): Khi nhấn vào các lớp thì sẽ hiện ra danh sách sinh viên
-- input: lecturer_id, semester_id, class_id
SELECT s.student_id, student_name, midpoint, finalpoint
FROM class_information
JOIN enroll USING (clazz_id)
JOIN student s USING (student_id)
WHERE lecturer_id = $1 AND semester_id = $2 AND clazz_id = $3;

-- Chấm điểm cho sinh viên
-- Step (1): hiện danh sách các lớp ở kì hiện tại
-- input: lecturer_id, semester_id
SELECT clazz_id, s.subject_id, subject_name
FROM class_information
JOIN subject s USING (subject_id)
WHERE lecturer_id = $1 AND semester_id = $2;
-- Step (2): Khi nhấn vào các lớp thì sẽ hiện ra danh sách sinh viên
-- input: lecturer_id, semester_id, class_id
SELECT s.student_id, student_name, midpoint, finalpoint
FROM class_information
JOIN enroll USING (clazz_id)
JOIN student s USING (student_id)
WHERE lecturer_id = $1 AND semester_id = $2 AND clazz_id = $3;
-- Step (3): Nhập điểm cho sinh viên
-- input: student_id, clazz_id, semester_id, (lecturer nhập: midpoint, finalpoint)
UPDATE enroll 
SET midpoint = ..., finalpoint = ...
WHERE student_id = $1 AND clazz_id = $2 AND semester_id = $3;

---------------------FORM TEACHER----------------------
-- Xem thông tin cá nhân
-- input: formteacher_id
SELECT formteacher_id, formteacher_name, gender, phone_number, institute_name
FROM form_teacher
JOIN institute USING (institute_id)
WHERE formteacher_id = $1;

-- Lấy danh sách sinh viên đã chủ nhiệm theo kỳ + đrl của sv
-- input: formteacher_id, semester_id
SELECT s.student_id, student_name, conduct_point
FROM give_conduct_point
JOIN student s USING (student_id)
WHERE formteacher_id = $1 AND semester_id = $2;

-- Chấm điểm rèn luyện cho sinh viên ở kỳ hiện tại
-- Step (1): Hiển thị danh sách sinh viên 
-- input: formteacher_id, semester_id
SELECT s.student_id, student_name, conduct_point
FROM give_conduct_point
JOIN student s USING (student_id)
WHERE formteacher_id = $1 AND semester_id = $2;
-- Step (2): Nhập điểm
-- input: student_id, semester_id (formteacher nhập conduct_point)
UPDATE give_conduct_point
SET conduct_point = ...
WHERE student_id = $1 AND semester_id = $2;

---------------------HEAD MASTER-----------------------
-- Thông tin cá nhân
-- input: headmaster_id
SELECT headmaster_id, headmaster_name, gender, phone_number, institute_name
FROM headmaster
JOIN institute USING (institute_id)
WHERE headmaster_id = $1;

-- Thêm một môn học
-- LƯU Ý: institute_id của subject được chèn thêm giống với institute của headmaster
INSERT INTO subject(subject_id, subject_name, credit, finalcoeffi) 
VALUES (..., ..., ..., ...);

-- Thêm các lớp cho môn học
INSERT INTO clazz(clazz_id, subject)
VALUES (..., ...)


-- Mở lớp cho kỳ KẾ TIẾP (nhập thông tin)
-- Step (1): Hiển thị danh sách các môn do headmaster này quản lý
-- input: headmaster_id
SELECT subject_id, subject_name
FROM subject
WHERE institute_id IN (SELECT institute_id FROM headmaster WHERE headmaster_id = $1);
-- Step (2): headmaster nhấn vào một subject nào đó. Lúc này danh sách các clazz của subject đó được hiển thị
-- input: subject_id
SELECT clazz_id
FROM clazz
WHERE subject_id = $1;
-- Step (3): headmaster nhấn vào một clazz nào đó.
-- Case 1: Nếu lecturer chưa được thêm cho clazz này thì headmaster phải nhập lecturer_id
-- Trong lệnh insert bên dưới, clazz_id được lấy từ clazz_id ở đầu bước 3, semester_id là semester_id kỳ sau. Headmaster chỉ nhập lecturer_id, room vfa max_student
INSERT INTO teach(clazz_id, semester_id, lecturer_id, room, max_student)
VALUES (..., ..., ..., ..., ...);
-- Case 2: Nếu lecturer đã được thêm cho clazz rồi thì headmaster sẽ nhập thông tin về thời gian
-- LƯU Ý: Một lớp có thể có nhiều thời gian học trong 1 tuần
INSERT INTO class_information(clazz_id, semester_id, dow, start_time, finish_time)
VALUES (..., ..., ...);
-- Headmaster có thể sửa thông tin cho các lớp học (kỳ kế tiếp)
UPDATE class_information
SET lecturer_id = ...,
	max_student = ...,
	room = ...,
	dow = ...,
	start_time = ...,
	finish_time = ...
WHERE clazz_id = $1 AND semester_id = $2;
-- Headmaster có thể xóa lớp học khỏi kỳ kế tiếp
-- Maybe nhấn vào icon thùng rác bên cạnh giáo viên
DELETE FROM teach
WHERE clazz_id = $1 AND semester_id = $2;
-- Headmaster có thể xóa thời gian học
-- Maybe nhấn vào icon thùng rác cạnh thời gian học
DELETE FROM study_time
WHERE clazz_id = $1 AND semester_id = $2 AND dow = $3 AND start_time = $4;



-- Phân công giáo viên chủ nhiệm cho học sinh ở kỳ kế tiếp
-- Step (1): Hiển thị dsach sinh viên
-- input: headmaster_id
SELECT student_id, student_name
FROM student
WHERE institute_id IN (SELECT institute_id FROM headmaster WHERE headmaster_id = $1);
-- Step (2): headmaster nhấn chọn student, sau đó nhập formteacher_id cho student
INSERT INTO give_conduct_point(formteacher_id, student_id, semester_id)
VALUES (..., $1, $2);
-- Có thể xóa 
DELETE FROM give_conduct_point
WHERE student = $1 AND semester_id = $2;

---------------------Admin-------------------
-- Đặt thời gian nhập điểm của giáo viên, thời gian đăng ký lớp của sinh viên
INSERT INTO semester(semester_id, start_enroll_time, finish_enroll_time, start_givepoint_time, finish_givepoint_time, start_semester_date, finish_semester_date)
VALUES (..., ..., ..., ..., ..., ..., ...);
---------------------TUTOR----------------------------
-- Xem bảng điểm của con mình
-- input: tutor_id
SELECT semester_id, t1.subject_id, subject_name, t1.credit, class_point, four_scale, alphabet_point
FROM subject_grades_of_students t1
JOIN subject USING (subject_id)
WHERE student_id = $1;

-- Xem thông tin của mình (thông tin phụ huynh học sinh)
-- input: tutor_id
SELECT father_name, father_dob, father_job, father_phonenumber, mother_name, mother_dob, mother_job, mother_phonenumber
FROM tutor
WHERE tutor_id = $1;

-- Xem thông tin giáo viên chủ nhiệm của con mình kỳ hiện tại
-- input: semester_id, tutor_id
SELECT f.formteacher_id, formteacher_name, gender, phone_number, institute_name
FROM give_conduct_point
JOIN form_teacher f USING (formteacher_id)
JOIN institute USING (institute_id)
WHERE student_id = $1 AND semester_id = $2;