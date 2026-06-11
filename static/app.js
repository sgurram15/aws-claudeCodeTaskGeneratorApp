document.addEventListener("DOMContentLoaded", function () {
    var form = document.getElementById("task-form");
    var taskList = document.getElementById("task-list");

    loadTasks();

    form.addEventListener("submit", function (e) {
        e.preventDefault();
        var data = {
            title: form.title.value,
            description: form.description.value,
            priority: form.priority.value,
        };
        var due = form.due_date.value;
        if (due) data.due_date = due;

        fetch("/api/tasks", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(data),
        })
            .then(function (res) {
                if (!res.ok) return res.json().then(function (err) { throw new Error(err.error); });
                return res.json();
            })
            .then(function () {
                form.reset();
                loadTasks();
            })
            .catch(function (err) {
                alert(err.message);
            });
    });

    function loadTasks() {
        fetch("/api/tasks")
            .then(function (res) { return res.json(); })
            .then(function (tasks) { renderTasks(tasks); });
    }

    function renderTasks(tasks) {
        if (tasks.length === 0) {
            taskList.innerHTML = '<li class="empty-state">No tasks yet. Add one above!</li>';
            return;
        }
        taskList.innerHTML = "";
        tasks.forEach(function (task) {
            var li = document.createElement("li");
            li.className = "task-card" + (task.status === "done" ? " done" : "");

            var checkbox = document.createElement("input");
            checkbox.type = "checkbox";
            checkbox.className = "task-toggle";
            checkbox.checked = task.status === "done";
            checkbox.setAttribute("aria-label", "Mark \"" + task.title + "\" as " + (task.status === "done" ? "open" : "done"));
            checkbox.addEventListener("change", function () { toggleTask(task); });

            var content = document.createElement("div");
            content.className = "task-content";

            var title = document.createElement("p");
            title.className = "task-title";
            title.textContent = task.title;
            content.appendChild(title);

            if (task.description) {
                var desc = document.createElement("p");
                desc.className = "task-description";
                desc.textContent = task.description;
                content.appendChild(desc);
            }

            var meta = document.createElement("div");
            meta.className = "task-meta";

            var badge = document.createElement("span");
            badge.className = "badge badge-" + task.priority;
            badge.textContent = task.priority;
            meta.appendChild(badge);

            if (task.due_date) {
                var due = document.createElement("span");
                due.className = "task-due";
                due.textContent = "Due: " + task.due_date;
                meta.appendChild(due);
            }

            content.appendChild(meta);

            var deleteBtn = document.createElement("button");
            deleteBtn.className = "task-delete";
            deleteBtn.textContent = "Delete";
            deleteBtn.setAttribute("aria-label", "Delete \"" + task.title + "\"");
            deleteBtn.addEventListener("click", function () { deleteTask(task.id); });

            li.appendChild(checkbox);
            li.appendChild(content);
            li.appendChild(deleteBtn);
            taskList.appendChild(li);
        });
    }

    function toggleTask(task) {
        var newStatus = task.status === "done" ? "open" : "done";
        fetch("/api/tasks/" + task.id, {
            method: "PUT",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ status: newStatus }),
        }).then(function () { loadTasks(); });
    }

    function deleteTask(id) {
        fetch("/api/tasks/" + id, { method: "DELETE" })
            .then(function () { loadTasks(); });
    }
});
