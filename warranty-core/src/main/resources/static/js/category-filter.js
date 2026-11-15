(() => {
    document.querySelectorAll('[data-category-filter]').forEach((filter) => {
        const group = filter.dataset.categoryFilter;
        const items = [...document.querySelectorAll(`[data-category-item="${group}"]`)];
        const buttons = [...filter.querySelectorAll('[data-category]')];

        buttons.forEach((button) => {
            const category = button.dataset.category;
            const count = items.filter((item) => category === 'all' || item.dataset.category === category).length;
            const countLabel = button.querySelector('[data-category-count]');
            if (countLabel) countLabel.textContent = count;
            button.addEventListener('click', () => {
                buttons.forEach((candidate) => candidate.setAttribute('aria-pressed', String(candidate === button)));
                items.forEach((item) => {
                    item.hidden = category !== 'all' && item.dataset.category !== category;
                });
            });
        });
    });
})();
